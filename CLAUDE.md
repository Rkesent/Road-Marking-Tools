# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of 3ds Max tools for road marking and terrain design, written in MAXScript. The tools are designed for 3D modeling workflows in 3ds Max, focusing on traffic guidance lines, terrain tools, and dashed road markings.

## Common Development Commands

### Loading Tools in 3ds Max
```maxscript
-- IMPORTANT: Always run in 3ds Max MAXScript Editor or Listener
-- Press F11 to open MAXScript Editor, or use MAXScript > MAXScript Editor menu

-- Load individual tools (recommended for development)
filein "TrafficGuideLine.ms"
filein "VShapeGenerator.ms" 
filein "DashedShape-2.0.0.ms"
filein "Terrain tool.ms"

-- Load all tools from current directory
files = getFiles @"*.ms"
for f in files do filein f

-- Load from specific path (replace with actual path)
files = getFiles @"C:\Users\[USER]\Desktop\CJ_HJ\Road-Marking-Tools\*.ms"
for f in files do filein f
```

### Function Definition Cleanup (Essential before reloading)
```maxscript
-- Critical: Clear all tool functions before reloading to prevent conflicts
-- TrafficGuideLine functions
try (calculateCenterPath = undefined) catch()
try (calculateVShapePositions = undefined) catch() 
try (createVShapeModel = undefined) catch()
try (analyzeSplineIntersection = undefined) catch()
try (tgl_calculateSingleVShapePoints = undefined) catch()

-- VShapeGenerator functions  
try (calculateVShapePoints = undefined) catch()
try (createVShapeGeometry = undefined) catch()
try (instanceVShapeOnSpline = undefined) catch()
try (calculateSingleVShapePoints = undefined) catch()

-- DashedShape functions
try (calculateDashedSegments = undefined) catch()

-- Terrain Tool functions (prefix: mlpt_)
try (mlpt_populate_path = undefined) catch()

-- Clear global variables if needed
try (tgl_previewEnabled = undefined) catch()
try (vsg_previewEnabled = undefined) catch()
try (ds_previewEnabled = undefined) catch()
```

### Quick Development Setup
```maxscript
-- Complete development reload sequence (run this block)
(
    -- Clear functions
    try (calculateCenterPath = undefined) catch()
    try (calculateVShapePoints = undefined) catch()
    try (calculateDashedSegments = undefined) catch()
    
    -- Set working directory (adjust path as needed)
    setCurrentDir @"C:\Users\[USER]\Desktop\CJ_HJ\Road-Marking-Tools\"
    
    -- Load all tools
    filein "TrafficGuideLine.ms"
    filein "VShapeGenerator.ms"
    filein "DashedShape-2.0.0.ms"
    filein "Terrain tool.ms"
    
    print "All tools loaded successfully!"
)
```

### Testing and Validation
```maxscript
-- Create test splines for TrafficGuideLine
-- Method 1: Use existing splines in scene
spline1 = $Line001  -- Select first boundary spline by name
spline2 = $Line002  -- Select second boundary spline by name
tgl_selectedSplines = #(spline1, spline2)
tgl_previewEnabled = true  -- Enable preview mode

-- Method 2: Use current selection
if selection.count >= 2 then (
    tgl_selectedSplines = #(selection[1], selection[2])
    tgl_previewEnabled = true
    print ("Selected splines: " + selection[1].name + ", " + selection[2].name)
) else (
    print "Please select at least 2 spline objects"
)

-- Test VShapeGenerator on selected spline  
if selection.count > 0 then (
    vsg_selectedSpline = selection[1]  -- Use first selected spline
    vsg_previewEnabled = true
    print ("Testing V-Shape on: " + selection[1].name)
) else (
    print "Please select a spline object first"
)

-- Test DashedShape
if selection.count > 0 then (
    ds_selectedObjs = #(selection[1])
    ds_previewEnabled = true
    print ("Testing Dashed Shape on: " + selection[1].name)
)

-- Quick validation check
fn validateSplineInputs splines =
(
    for s in splines do (
        if s == undefined then (
            print "ERROR: Undefined spline found"
            return false
        )
        if not isKindOf s Shape then (
            print ("ERROR: Object " + s.name + " is not a Shape/Spline")
            return false  
        )
    )
    print "All spline inputs are valid"
    return true
)
```

## Architecture

### Core Components

**TrafficGuideLine.ms** - Main traffic guidance line generator (v1.0.0)
- Creates V-shaped traffic guide lines between two splines
- Supports two modes: offset mode (dynamic based on spline boundaries) and fixed skeleton mode (standard V-shapes)
- Features real-time preview system with viewport callbacks
- Handles spline intersection analysis and generates closure lines when boundaries don't meet
- Core algorithms in `calculateCenterPath`, `calculateVShapePositions`, and `createVShapeModel`
- Integrates with VShapeGenerator for enhanced V-shape calculation using `calculateSingleVShapePoints`

**VShapeGenerator.ms** - V-shape line segment generator (v1.0.0)
- Generates adjustable V-shaped line segments and instances them onto splines
- Supports configurable arm length, AC distance, and instance spacing parameters
- Features dual V-shape generation with controllable spacing between V-shapes
- Includes spline-to-surface conversion capabilities for road marking visualization
- Core functions: `calculateVShapePoints`, `createVShapeGeometry`, `instanceVShapeOnSpline`

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
filein "VShapeGenerator.ms"
filein "DashedShape-2.0.0.ms" 
filein "Terrain tool.ms"

-- Or load all tools at once
fileIn @"C:\path\to\Road-Marking-Tools\*.ms"
```

### Global Variable Management
Each tool uses prefixed global variables to avoid conflicts:
- **TrafficGuideLine**: `tgl_*` prefix (e.g., `tgl_previewEnabled`, `tgl_vSpacing`)
- **VShapeGenerator**: `vsg_*` prefix (e.g., `vsg_armLength`, `vsg_acDistance`, `vsg_instanceSpacing`)
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
- Preview enabled through tool-specific global flags (`tgl_previewEnabled`, `vsg_previewEnabled`, `ds_previewEnabled`)
- Uses `drawTrafficGuidePreview` and viewport callbacks for real-time visualization
- Automatically registers/unregisters viewport callbacks on dialog open/close
- Color-coded previews: Traffic Guide (yellow), V-Shape Generator (orange), Dashed Shape (green)

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

**VShapeGenerator Parameters**:
- Configurable arm length (default 300mm) and AC distance (default 200mm) for precise V-shape geometry
- Instance spacing controls placement frequency along splines (default 500mm)
- Dual V-shape mode with adjustable spacing between paired V-shapes (default 200mm)
- Surface generation with configurable width (100mm) and subdivision count (20) for mesh optimization

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

**TrafficGuideLine v1.0.0**: Complete rewrite with improved intersection analysis and VShapeGenerator integration
**VShapeGenerator v1.0.0**: New component for enhanced V-shape calculation and spline-to-surface conversion
**DashedShape v2.0.0**: Major refactor ensuring preview-generation algorithm consistency  
**Terrain Tool v1.5**: Performance optimizations with cached mesh operations

## Supporting Documentation

- `中心线生成算法文档.md`: Detailed algorithm analysis with mathematical explanations
- Contains algorithmic deep-dive into center path calculation, V-shape positioning, and geometric generation methods
- Essential reference for understanding the mathematical foundations of the traffic guide line generation

## Common Issues and Solutions

### MAXScript Environment Issues

**Problem**: "Cannot open file" or "filein" errors
```maxscript
-- Solution 1: Verify file path and set current directory
print (getCurrentDir())  -- Check current directory
setCurrentDir @"C:\path\to\Road-Marking-Tools\"  -- Set correct path

-- Solution 2: Use absolute paths
filein @"C:\full\path\to\TrafficGuideLine.ms"
```

**Problem**: Function conflicts or "already defined" warnings
```maxscript
-- Solution: Clear functions before reloading (as shown above)
try (calculateCenterPath = undefined) catch()
-- Or restart 3ds Max for complete cleanup
```

**Problem**: Preview callbacks not cleaning up properly
```maxscript
-- Solution: Manual cleanup of all viewport callbacks
unregisterRedrawViewsCallback id:#TrafficGuidePreview
unregisterRedrawViewsCallback id:#VShapePreview
unregisterRedrawViewsCallback id:#DashedShapePreview
```

### Geometry Generation Issues

**Problem**: V-shapes not appearing or positioned incorrectly
- Check that input objects are Shape objects (splines), not geometry
- Verify splines have proper direction and are not self-intersecting
- Ensure system units are set correctly (mm recommended)
- Test with simple Line or Rectangle shapes first

**Problem**: Performance issues with complex splines
- Reduce preview quality for complex curves (fewer sample points)
- Use linear interpolation mode in DashedShape for better performance
- Consider splitting complex splines into simpler segments

### Development Workflow Issues

**Problem**: Changes not taking effect
- Always clear global variables and function definitions before reloading
- Check MAXScript Listener for error messages
- Verify tool dialogs are closed before reloading scripts

**Problem**: Missing dependencies or function not found errors
- Ensure all required tools are loaded in correct order
- TrafficGuideLine depends on VShapeGenerator for enhanced calculations
- Check global variable prefixes to avoid naming conflicts