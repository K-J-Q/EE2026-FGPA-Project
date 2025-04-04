`timescale 1ns / 1ps

module drawCordinate (
    input  [12:0] cordinateIndex,
    input  [ 7:0] userX,
    input  [ 7:0] userY,
    input  [ 7:0] botX,
    input  [ 7:0] botY,
    input  [95:0] wall_tiles,
    input  [95:0] breakable_tiles,
    input  [95:0] bomb_tiles,
    output [15:0] oledColour
);

import sprites::*;

  parameter BLACK  = 16'h0000;
  parameter RED    = 16'hF800;
  parameter WHITE  = 16'hFFFF;
  parameter GREEN  = 16'h07E0;
  parameter BLUE   = 16'h001F;
  parameter YELLOW = 16'hFFE0;

  parameter TILE_WIDTH  = 8;  // 96/12 = 8 pixels per tile width
  parameter TILE_HEIGHT = 8;  // 64/8 = 8 pixels per tile height
  parameter GRID_WIDTH  = 12;
  parameter GRID_HEIGHT = 8;

  wire [15:0] userSquareColour;
  wire [15:0] botSquareColour;  // new wire for bot square
  wire [15:0] objectColour;

  // Calculate current pixel coordinates
  wire [6:0] pixelX = cordinateIndex % 96;
  wire [6:0] pixelY = cordinateIndex / 96;

  // Calculate which tile the current pixel belongs to
  wire [3:0] tileX = pixelX / TILE_WIDTH;
  wire [3:0] tileY = pixelY / TILE_HEIGHT;
  wire [6:0] tileIndex = (tileY * GRID_WIDTH) + tileX;

  wire isWall = wall_tiles[tileIndex];
  wire isBreakable = breakable_tiles[tileIndex];
  wire isBomb = bomb_tiles[tileIndex];

  // Calculate local coordinates within an 8x8 tile
  wire [2:0] localX = pixelX % TILE_WIDTH;
  wire [2:0] localY = pixelY % TILE_HEIGHT;
  wire [5:0] tilePixelIndex = localY * TILE_WIDTH + localX;
  
  // Determine active sprite pixel for wall and breakable using sprites data.
  wire wallActive = isWall && (WALL_SPRITE_DATA[tilePixelIndex]);
  wire brickActive = isBreakable && (BRICK_SPRITE_DATA[tilePixelIndex]);

  // Assign color based on tile type: bomb has highest priority.
  assign objectColour = isBomb ? WHITE : 
                        (~wallActive & isWall ? BLUE : 
                        (~brickActive & isBreakable ? RED : BLACK));

  // Instantiate drawSquare for user and bot blocks
  drawSquare #(8) userSquare (
      .x(userX),
      .y(userY),
      .colour(GREEN),
      .squareData(CAT_SPRITE_DATA),
      .cordinateIndex(cordinateIndex),
      .oledColour(userSquareColour)
  );

  drawSquare #(8) botSquare (
      .x(botX),
      .y(botY),
      .colour(YELLOW),
      .squareData(DINO_SPRITE_DATA),
      .cordinateIndex(cordinateIndex),
      .oledColour(botSquareColour)
  );
  
  // Combine elements with priority: bot, user, then wall
  assign oledColour = botSquareColour | userSquareColour | objectColour;
endmodule
