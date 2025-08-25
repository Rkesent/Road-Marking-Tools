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

**DashedShape-2.0.0.ms** - Dashed line pattern generator (v2.0.0)
- Creates dashed road marking patterns with configurable solid/gap lengths
- Unified preview and generation algorithm for consistency
- Supports linear interpolation mode and special continuous line cases (gap=0)
- Core algorithm in `calculateDashedSegments` with real-time preview system

**Terrain tool.ms** - Advanced terrain population and mesh utilities (v1.5)
- Terrain filling and mesh processing tools with optimized polyOp/meshOp operations
- Configuration-driven with INI settings support
- Cached geometry operations for performance optimization
- Professional terrain modeling workflow integration

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

### Loading and Testing Tools
```maxscript
-- Load individual tools in 3ds Max script editor
filein "TrafficGuideLine.ms"
filein "DashedShape-2.0.0.ms" 
filein "Terrain tool.ms"

-- Or load all tools at once
fileIn @"C:\path\to\Road-Marking-Tools\*.ms"
```

### Global Variable Management
Each tool uses prefixed global variables to avoid conflicts:
- **TrafficGuideLine**: `tgl_*` prefix (e.g., `tgl_previewEnabled`, `tgl_vSpacing`)
- **DashedShape**: `ds_*` prefix (e.g., `ds_solidLength`, `ds_gapLength`)  
- **Terrain Tool**: `mlpt_*` prefix (e.g., `mlpt_populate_path`)

**Important**: Always clear function definitions before reloading:
```maxscript
try (functionName = undefined) catch()
```

### Debugging and Development
- All tools include comprehensive error handling with try-catch blocks
- Use `print` statements for debugging algorithm flows
- Preview systems use viewport callbacks - ensure proper cleanup on dialog close
- Test with various spline configurations to validate intersection algorithms

### Key Parameters
- All measurements use 3ds Max system units (typically mm)
- V-shape parameters: offset (0-10000), spacing (100-1000), thickness (10-500)
- Standard V-shape: 300mm arm length, 60° angle, 100mm width

### Preview System and UI Architecture
- Preview enabled through tool-specific global flags (`tgl_previewEnabled`, `ds_previewEnabled`)
- Uses `drawTrafficGuidePreview` and viewport callbacks for real-time visualization
- Automatically registers/unregisters viewport callbacks on dialog open/close
- Color-coded previews: Traffic Guide (yellow), Dashed Shape (green)

### Algorithm Characteristics and Constraints

**TrafficGuideLine Constraints**:
- Requires exactly 2 Shape objects (splines) as boundary input
- Intersection tolerance set to 50 system units for spline endpoint detection
- Center path calculated with 50-point sampling for precision
- V-shape spacing must be greater than closure buffer (0.5 * spacing) to generate valid results
- Fixed angle mode uses standard 300mm arm length, 60° angle, 100mm width

**DashedShape Optimization**:
- Unified algorithm ensures preview-generation consistency in v2.0.0
- Special case handling for gap=0 (continuous lines) vs gap>0 (dashed patterns)
- Linear interpolation mode available for complex curve scenarios
- Memory-efficient segment calculation without intermediate geometry creation

**Terrain Tool Performance**:
- Cached polyOp/meshOp operations reduce memory leaks and improve speed
- INI-based configuration for persistent settings across sessions
- Optimized for large mesh processing workflows

## Important Notes

- Tools expect Shape objects (splines) as input for boundary definition
- All geometry creation includes proper material ID assignment
- Error handling with try-catch blocks and user-friendly messages
- Global variables prefixed with tool abbreviations to avoid conflicts
- Objects are automatically grouped for easy scene management
- Z-coordinates maintained consistently across all generated geometry

## Version History and Key Changes

**TrafficGuideLine v1.0.0**: Complete rewrite with improved intersection analysis
**DashedShape v2.0.0**: Major refactor ensuring preview-generation algorithm consistency  
**Terrain Tool v1.5**: Performance optimizations with cached mesh operations

## Supporting Documentation

- `中心线生成算法文档.md`: Detailed algorithm analysis with mathematical explanations
- Contains algorithmic deep-dive into center path calculation, V-shape positioning, and geometric generation methods
- Essential reference for understanding the mathematical foundations of the traffic guide line generation