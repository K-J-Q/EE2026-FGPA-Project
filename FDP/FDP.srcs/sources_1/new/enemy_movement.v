`timescale 1ns / 1ps

module enemy_movement (
    input clk,
    input en,
    input [6:0] bot_index,
    input [6:0] user_index,
    input [41:0] bomb_indices,  // Updated to handle up to 6 bombs
    input [5:0] bomb_en,        // Updated to handle up to 6 bombs
    input [95:0] wall_tiles,
    input [95:0] breakable_tiles,
    input [15:0] random_number,
    output reg dropBomb,
    output reg [2:0] direction
);
  // Grid parameters
  parameter GRID_WIDTH = 12;
  parameter GRID_HEIGHT = 8;
  parameter CHASE_RANGE = 3;

  // State definitions
  parameter IDLE = 3'b000;
  parameter PATROLLING = 3'b001;
  parameter CHASING = 3'b010;
  parameter FLEEING = 3'b011;

  // Direction definitions
  parameter NO_MOVE = 3'd0;
  parameter UP = 3'd1;
  parameter RIGHT = 3'd2;
  parameter DOWN = 3'd3;
  parameter LEFT = 3'd4;

  // State registers
  reg [2:0] current_state = IDLE;
  reg [2:0] next_state = IDLE;
  
  // Counters
  reg [1:0] patrol_after_flee_counter = 0;  // Counter to track PATROLLING cycles after FLEEING

  // Position and movement tracking
  reg [3:0] new_botX;
  reg [3:0] new_botY;

  // Extract X/Y coordinates from indices for easier comparison
  wire [3:0] botX = bot_index % GRID_WIDTH;
  wire [3:0] botY = bot_index / GRID_WIDTH;
  wire [3:0] userX = user_index % GRID_WIDTH;
  wire [3:0] userY = user_index / GRID_WIDTH;

  // Extract bomb X/Y coordinates from indices for easier comparison
  wire [3:0] bomb_X[5:0];  // Increased to handle up to 6 bombs
  wire [3:0] bomb_Y[5:0];  // Increased to handle up to 6 bombs

  // Map all 6 potential bomb positions (3 player bombs, 3 enemy bombs)
  assign bomb_X[0] = bomb_indices[6:0] % GRID_WIDTH;
  assign bomb_Y[0] = bomb_indices[6:0] / GRID_WIDTH;
  assign bomb_X[1] = bomb_indices[13:7] % GRID_WIDTH;
  assign bomb_Y[1] = bomb_indices[13:7] / GRID_WIDTH;
  assign bomb_X[2] = bomb_indices[20:14] % GRID_WIDTH;
  assign bomb_Y[2] = bomb_indices[20:14] / GRID_WIDTH;
  assign bomb_X[3] = bomb_indices[27:21] % GRID_WIDTH;
  assign bomb_Y[3] = bomb_indices[27:21] / GRID_WIDTH;
  assign bomb_X[4] = bomb_indices[34:28] % GRID_WIDTH;
  assign bomb_Y[4] = bomb_indices[34:28] / GRID_WIDTH;
  assign bomb_X[5] = bomb_indices[41:35] % GRID_WIDTH;
  assign bomb_Y[5] = bomb_indices[41:35] / GRID_WIDTH;

  // Distance calculation to player
  wire [3:0] dx_player = (botX > userX) ? (botX - userX) : (userX - botX);
  wire [3:0] dy_player = (botY > userY) ? (botY - userY) : (userY - botY);
  wire [3:0] dist_to_player = dx_player + dy_player;

  // Bomb danger detection - check if bot is in line with any active bomb
  wire [5:0] bomb_danger;  // One bit per bomb
  
  // Check each bomb to see if the bot is in its blast line
  genvar i;
  generate
    for (i = 0; i < 6; i = i + 1) begin : bomb_check
      assign bomb_danger[i] = bomb_en[i] && ((botX == bomb_X[i]) || (botY == bomb_Y[i]));
    end
  endgenerate
  
  // Bot is in danger if any bomb danger bit is set
  wire in_bomb_danger = |bomb_danger;

  // Collision detection function
  function is_collision;
    input [3:0] test_x, test_y;
    reg [6:0] tile_index;
    begin
      tile_index   = test_y * GRID_WIDTH + test_x;
      is_collision = (tile_index < 96) && (wall_tiles[tile_index] || breakable_tiles[tile_index]);
    end
  endfunction

  // Helper function to detect if position is in bomb line
  function is_in_bomb_line;
      input [3:0] test_x, test_y;
      integer i;
      begin
        is_in_bomb_line = 0; // Initialize to false
        for (i = 0; i < 6; i = i + 1) begin
          if (bomb_en[i] && ((test_x == bomb_X[i]) || (test_y == bomb_Y[i]))) begin
            is_in_bomb_line = 1; // Set to true if any bomb matches
          end
        end
      end
  endfunction

    function is_clear_path;
      input [3:0] start_x, start_y;
      input [3:0] end_x, end_y;
      integer i;
      reg [3:0] min, max;
      begin
          if (start_y == end_y) begin // horizontal line-of-sight
              if (start_x < end_x) begin
                  min = start_x;
                  max = end_x;
              end else begin
                  min = end_x;
                  max = start_x;
              end
              is_clear_path = 1;
              // Fixed loop from 0 to 15
              for (i = 0; i < 16; i = i + 1) begin
                  if ((i > min) && (i < max)) begin
                      if (is_collision(i, start_y))
                          is_clear_path = 0;
                  end
              end
          end else if (start_x == end_x) begin // vertical line-of-sight
              if (start_y < end_y) begin
                  min = start_y;
                  max = end_y;
              end else begin
                  min = end_y;
                  max = start_y;
              end
              is_clear_path = 1;
              // Fixed loop from 0 to 15
              for (i = 0; i < 16; i = i + 1) begin
                  if ((i > min) && (i < max)) begin
                      if (is_collision(start_x, i))
                          is_clear_path = 0;
                  end
              end
          end else begin
              // Not aligned horizontally or vertically.
              is_clear_path = 0;
          end
      end
  endfunction

  // Helper function to check if a move is safe (no collision, no bomb, and within map boundaries)
  function is_safe_move;
    input [3:0] test_x, test_y;
    begin
      is_safe_move = (test_x < GRID_WIDTH) && (test_y < GRID_HEIGHT) &&
          ~is_collision(test_x, test_y) && ~is_in_bomb_line(test_x, test_y);
    end
  endfunction

  // State machine - next state logic
  always @(*) begin
    next_state = current_state;

    if (en) begin
      case (current_state)
        IDLE: begin
          if (dist_to_player <= CHASE_RANGE) next_state = CHASING;
          else if (random_number[15:13] != 3'b111) next_state = PATROLLING;
        end

        PATROLLING: begin
          if (in_bomb_danger) next_state = FLEEING;
          else if (patrol_after_flee_counter > 0) next_state = PATROLLING;
          else if (dist_to_player <= CHASE_RANGE) next_state = CHASING;
          else if (random_number[15:14] == 2'b00) next_state = IDLE;
        end

        CHASING: begin
          if (dist_to_player > CHASE_RANGE) next_state = PATROLLING;
          else if (in_bomb_danger) next_state = FLEEING;
        end

        FLEEING: begin
          if (~in_bomb_danger) next_state = PATROLLING;
        end
      endcase
    end
  end

  // State machine - state update and counter management
  always @(posedge clk) begin
    if (en) begin
      current_state <= next_state;

      // Handle patrol after flee counter
      if (current_state == FLEEING && next_state == PATROLLING) begin
        patrol_after_flee_counter <= 3;  // Initialize counter for 3 cycles of patrolling after fleeing
      end else if (patrol_after_flee_counter > 0) begin
        patrol_after_flee_counter <= patrol_after_flee_counter - 1;
      end

      // Determine movement based on state
      case (current_state)
        IDLE: direction <= NO_MOVE;

        PATROLLING: handle_patrol_movement();

        CHASING: handle_chase_movement();

        FLEEING: handle_flee_movement();
      endcase

      // Calculate new position based on current direction
      calculate_new_position();

      // Determine if a bomb should be dropped
      handle_bomb_dropping();
    end else begin
      // When not enabled, stay in place and don't drop bombs
      direction <= NO_MOVE;
      dropBomb <= 0;
    end
  end

  // Modified task handle_patrol_movement to set NO_MOVE if everywhere is unsafe
  task handle_patrol_movement;
    reg [3:0] dir_order;
    reg safe_up, safe_right, safe_down, safe_left;
    begin
      // Check which directions are safe
      safe_up    = is_safe_move(botX, botY - 1);
      safe_right = is_safe_move(botX + 1, botY);
      safe_down  = is_safe_move(botX, botY + 1);
      safe_left  = is_safe_move(botX - 1, botY);
      
      // If all directions are unsafe, set direction to NO_MOVE
      if (~safe_up && ~safe_right && ~safe_down && ~safe_left) begin
        direction <= NO_MOVE;
      end else begin
        // Use random number to determine direction selection pattern
        case (random_number[2:0])
          0: begin  // Check UP -> RIGHT -> DOWN -> LEFT
            if (safe_up) direction <= UP;
            else if (safe_right) direction <= RIGHT;
            else if (safe_down) direction <= DOWN;
            else if (safe_left) direction <= LEFT;
            else direction <= NO_MOVE;
          end

          1: begin  // Check RIGHT -> DOWN -> LEFT -> UP
            if (safe_right) direction <= RIGHT;
            else if (safe_down) direction <= DOWN;
            else if (safe_left) direction <= LEFT;
            else if (safe_up) direction <= UP;
            else direction <= NO_MOVE;
          end

          2: begin  // Check DOWN -> LEFT -> UP -> RIGHT
            if (safe_down) direction <= DOWN;
            else if (safe_left) direction <= LEFT;
            else if (safe_up) direction <= UP;
            else if (safe_right) direction <= RIGHT;
            else direction <= NO_MOVE;
          end

          3: begin  // Check LEFT -> UP -> RIGHT -> DOWN
            if (safe_left) direction <= LEFT;
            else if (safe_up) direction <= UP;
            else if (safe_right) direction <= RIGHT;
            else if (safe_down) direction <= DOWN;
            else direction <= NO_MOVE;
          end

          4: begin  // Check UP -> LEFT -> DOWN -> RIGHT
            if (safe_up) direction <= UP;
            else if (safe_left) direction <= LEFT;
            else if (safe_down) direction <= DOWN;
            else if (safe_right) direction <= RIGHT;
            else direction <= NO_MOVE;
          end

          5: begin  // Check DOWN -> RIGHT -> UP -> LEFT
            if (safe_down) direction <= DOWN;
            else if (safe_right) direction <= RIGHT;
            else if (safe_up) direction <= UP;
            else if (safe_left) direction <= LEFT;
            else direction <= NO_MOVE;
          end

          default: begin  // Random selection based on more bits
            if (random_number[3]) begin
              if (random_number[4] ? safe_up : safe_down) direction <= random_number[4] ? UP : DOWN;
              else if (random_number[5] ? safe_left : safe_right)
                direction <= random_number[5] ? LEFT : RIGHT;
              else if (random_number[4] ? safe_down : safe_up)
                direction <= random_number[4] ? DOWN : UP;
              else if (random_number[5] ? safe_right : safe_left)
                direction <= random_number[5] ? RIGHT : LEFT;
              else direction <= NO_MOVE;
            end else begin
              if (random_number[6] ? safe_left : safe_right)
                direction <= random_number[6] ? LEFT : RIGHT;
              else if (random_number[7] ? safe_up : safe_down)
                direction <= random_number[7] ? UP : DOWN;
              else if (random_number[6] ? safe_right : safe_left)
                direction <= random_number[6] ? RIGHT : LEFT;
              else if (random_number[7] ? safe_down : safe_up)
                direction <= random_number[7] ? DOWN : UP;
              else direction <= NO_MOVE;
            end
          end
        endcase
      end
    end
  endtask

  // Handle chase movement logic - move toward player when in range
  task handle_chase_movement;
    begin
      if (dx_player == 0 && dy_player == 0) direction <= NO_MOVE;
      else if (dx_player > dy_player) begin
        // Prioritize horizontal movement
        if (botX < userX) begin
          if (is_safe_move(botX + 1, botY)) direction <= RIGHT;
          else if (botY < userY && is_safe_move(botX, botY + 1)) direction <= DOWN;
          else if (is_safe_move(botX, botY - 1)) direction <= UP;
          else direction <= NO_MOVE;
        end else begin
          if (is_safe_move(botX - 1, botY)) direction <= LEFT;
          else if (botY < userY && is_safe_move(botX, botY + 1)) direction <= DOWN;
          else if (is_safe_move(botX, botY - 1)) direction <= UP;
          else direction <= NO_MOVE;
        end
      end else begin
        // Prioritize vertical movement
        if (botY < userY) begin
          if (is_safe_move(botX, botY + 1)) direction <= DOWN;
          else if (botX < userX && is_safe_move(botX + 1, botY)) direction <= RIGHT;
          else if (is_safe_move(botX - 1, botY)) direction <= LEFT;
          else direction <= NO_MOVE;
        end else begin
          if (is_safe_move(botX, botY - 1)) direction <= UP;
          else if (botX < userX && is_safe_move(botX + 1, botY)) direction <= RIGHT;
          else if (is_safe_move(botX - 1, botY)) direction <= LEFT;
          else direction <= NO_MOVE;
        end
      end
    end
  endtask

  // Handle flee movement logic - move away from bombs
  task handle_flee_movement;
    reg [3:0] safe_directions;
    begin
      // Initialize safe directions bitmap (UP, RIGHT, DOWN, LEFT)
      safe_directions[0] = is_safe_move(botX, botY - 1);
      safe_directions[1] = is_safe_move(botX + 1, botY);
      safe_directions[2] = is_safe_move(botX, botY + 1);
      safe_directions[3] = is_safe_move(botX - 1, botY);

      // Prioritize movement to directions that are perpendicular to bomb blast line
      if (safe_directions[0] && safe_directions[3]) begin
        direction <= UP;  // Move up if both up and left are safe
      end else if (safe_directions[1] && safe_directions[2]) begin
        direction <= RIGHT;  // Move right if both right and down are safe
      end else if (safe_directions[2] && safe_directions[3]) begin
        direction <= DOWN;  // Move down if both down and left are safe
      end else if (safe_directions[0] && safe_directions[1]) begin
        direction <= LEFT;  // Move left if both up and right are safe
      end else begin
        // If no safe direction is found, move in any possible one
        direction <= random_number[1:0];
        if (safe_directions[0]) begin
          direction <= UP;
        end else if (safe_directions[1]) begin
          direction <= RIGHT;
        end else if (safe_directions[2]) begin
          direction <= DOWN;
        end else if (safe_directions[3]) begin
          direction <= LEFT;
        end else begin
          // move anywhere without collision
          if (~is_collision(botX, botY - 1)) begin
            direction <= UP;
          end else if (~is_collision(botX + 1, botY)) begin
            direction <= RIGHT;
          end else if (~is_collision(botX, botY + 1)) begin
            direction <= DOWN;
          end else if (~is_collision(botX - 1, botY)) begin
            direction <= LEFT;
          end else begin
            direction <= NO_MOVE;  // No safe move available
          end
        end
      end
    end
  endtask

  // Calculate new position based on current direction
  task calculate_new_position;
    begin
      case (direction)
        UP: begin
          new_botX = botX;
          new_botY = botY - 1;
        end
        RIGHT: begin
          new_botX = botX + 1;
          new_botY = botY;
        end
        DOWN: begin
          new_botX = botX;
          new_botY = botY + 1;
        end
        LEFT: begin
          new_botX = botX - 1;
          new_botY = botY;
        end
        default: begin
          new_botX = botX;
          new_botY = botY;
        end
      endcase
    end
  endtask
    wire [6:0] new_bot_index = new_botY * GRID_WIDTH + new_botX;

  // Handle bomb dropping logic
  task handle_bomb_dropping;
    begin
      // Only drop bomb if aligned with the user, the random condition passes,
      // the path is clear of walls/breakable tiles, and the bot isn't already in a bomb line.
      dropBomb <= ((new_botX == userX || new_botY == userY) &
                   (random_number[3:0] < 4'b1000) &
                   is_clear_path(new_botX, new_botY, userX, userY)) &
                   (~is_in_bomb_line(new_botX, new_botY));
    end
  endtask

endmodule
