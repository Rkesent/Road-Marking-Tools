# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of 3ds Max tools for road marking and terrain design, written in MAXScript. The tools are designed for 3D modeling workflows in 3ds Max, focusing on traffic guidance lines, terrain tools, and dashed road markings.

## Architecture

### Core Components

**TrafficGuideLine.ms** - Main traffic guidance line generator (v1.0.0)
- Creates V-shaped traffic guide lines between two splines
- Supports two modes: offset mode (dynamic based on spline boundaries) and fixed skeleton mode (standard V-shapes)
- Features real-time preview system with viewport callbacks
- Handles spline intersection analysis and generates closure lines when boundaries don't meet
- Core algorithms in `calculateCenterPath`, `calculateVShapePositions`, and `createVShapeModel`

**DashedShape-2.0.0.ms** - Dashed line pattern generator
- Creates dashed road marking patterns
- Likely handles standard road marking specifications

**Terrain tool.ms** - Terrain modeling utilities
- Tools for terrain generation and modification

### Key Algorithms

1. **Center Path Calculation** (`calculateCenterPath`): Interpolates points between two boundary splines to create the center guideline
2. **V-Shape Positioning** (`calculateVShapePositions`): Calculates optimal placement of V-shapes along the path, considering closure areas and spacing
3. **Geometric Generation**: 
   - `createVShapeModel`: Creates 3D mesh geometry for V-shapes with proper normals and materials
   - `createStandardVShape`: Generates fixed-angle V-shapes with standard dimensions
   - `createClosureLine`: Creates connecting lines between non-intersecting spline endpoints

### UI Architecture

- Uses MAXScript rollouts for tool interfaces
- Real-time preview system using viewport redraw callbacks (`registerRedrawViewsCallback`)
- Parameter validation and user feedback through message boxes
- Automatic cleanup of preview callbacks on dialog close

## Development Workflow

### Testing MAXScript Tools
```maxscript
-- Load and test tools in 3ds Max script editor
filein "TrafficGuideLine.ms"
filein "DashedShape-2.0.0.ms" 
filein "Terrain tool.ms"
```

### Key Parameters
- All measurements use 3ds Max system units (typically mm)
- V-shape parameters: offset (0-10000), spacing (100-1000), thickness (10-500)
- Standard V-shape: 300mm arm length, 60° angle, 100mm width

### Preview System
- Preview enabled through `tgl_previewEnabled` global flag
- Uses `drawTrafficGuidePreview` for real-time visualization
- Automatically registers/unregisters viewport callbacks

## Important Notes

- Tools expect Shape objects (splines) as input for boundary definition
- All geometry creation includes proper material ID assignment
- Error handling with try-catch blocks and user-friendly messages
- Global variables prefixed with tool abbreviations (e.g., `tgl_` for TrafficGuideLine)
- Objects are automatically grouped for easy management
- Z-coordinates maintained consistently across all generated geometry