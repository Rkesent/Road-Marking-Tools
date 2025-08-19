-------
-- TrafficGuideLine v1.0.0 - 车道导流线生成器
-- 功能：基于两条样条线生成V字形导流线标记
-------

-- 全局变量
global tgl_previewColor = color 255 255 0  -- 黄色预览线条
global tgl_selectedSplines = #()
global tgl_previewEnabled = false
global tgl_vLength = 800          -- V字形长度 (mm)
global tgl_vWidth = 400           -- V字形宽度 (mm)
global tgl_vSpacing = 1200        -- V字形间距 (mm)
global tgl_lineThickness = 100    -- 线条粗细 (mm)
global tgl_vDirection = 1         -- V字形方向 (1=正向, -1=反向)

-------
-- 核心算法：计算两条样条线之间的中心路径
-------
fn calculateCenterPath spline1 spline2 =
(
    local centerPoints = #()
    local spline1Length = curveLength spline1 1
    local spline2Length = curveLength spline2 1
    local maxLength = amax spline1Length spline2Length
    
    if maxLength > 0 then
    (
        -- 沿路径采样点，计算中心线
        local sampleCount = 50  -- 采样点数量
        for i = 0 to sampleCount do
        (
            local param = i as float / sampleCount as float
            
            -- 在两条样条线上获取对应点
            local pos1 = lengthInterp spline1 1 param
            local pos2 = lengthInterp spline2 1 param
            
            -- 计算中心点
            local centerPos = (pos1 + pos2) / 2.0
            append centerPoints centerPos
        )
    )
    
    return centerPoints
)

-------
-- 计算路径宽度（两条样条线之间的距离）
-------
fn calculatePathWidth spline1 spline2 param =
(
    local pos1 = lengthInterp spline1 1 param
    local pos2 = lengthInterp spline2 1 param
    return distance pos1 pos2
)

-------
-- 生成单个V字形几何体（使用实际边界点，底部顶点焊接）
-------
fn createVShapeGeometry centerPos direction leftBoundary rightBoundary vLength lineThick =
(
    local verts = #()
    local faces = #()
    
    -- 计算V字形的基本尺寸
    local halfLength = vLength / 2.0
    local halfThick = lineThick / 2.0
    local lineWidth = lineThick * 0.8  -- V字线条的宽度
    local halfLineWidth = lineWidth / 2.0
    
    -- 计算V字形的关键点
    local centerBottom = centerPos - direction * halfLength  -- V字底部中心点
    
    -- 计算V字形顶部位置，使其对齐到边界样条线
    local topPos = centerPos + direction * halfLength
    local leftTop = leftBoundary + (topPos.z - leftBoundary.z) * [0,0,1]   -- 左上端点对齐到左边界
    local rightTop = rightBoundary + (topPos.z - rightBoundary.z) * [0,0,1]  -- 右上端点对齐到右边界
    
    -- 计算左臂的方向向量
    local leftArmDir = normalize (leftTop - centerBottom)
    local leftArmPerp = normalize (cross leftArmDir [0,0,1])
    
    -- 计算右臂的方向向量
    local rightArmDir = normalize (rightTop - centerBottom)
    local rightArmPerp = normalize (cross rightArmDir [0,0,1])
    
    -- 关键修复：左右臂内侧底部顶点焊接
    -- 计算左臂和右臂的各个角点
    local leftBottomOuter = centerBottom - leftArmPerp * halfLineWidth
    local leftBottomInner = centerBottom + leftArmPerp * halfLineWidth
    local rightBottomOuter = centerBottom + rightArmPerp * halfLineWidth
    local rightBottomInner = centerBottom - rightArmPerp * halfLineWidth
    
    -- 焊接点：左右臂内侧底点焊接到centerBottom位置
    local weldedBottomInner = centerBottom  -- 直接使用中心底部点作为焊接点
    
    -- 左臂的角点
    local leftTopInner = leftTop - leftArmPerp * halfLineWidth
    local leftTopOuter = leftTop + leftArmPerp * halfLineWidth
    
    -- 右臂的角点
    local rightTopInner = rightTop + rightArmPerp * halfLineWidth
    local rightTopOuter = rightTop - rightArmPerp * halfLineWidth
    
    -- 创建底面顶点
    append verts (weldedBottomInner - [0,0,halfThick])      -- 1: 焊接的内侧底点（底面）
    append verts (leftBottomOuter - [0,0,halfThick])       -- 2: 左臂外底点（底面）
    append verts (leftTopOuter - [0,0,halfThick])          -- 3: 左臂外顶点（底面）
    append verts (leftTopInner - [0,0,halfThick])          -- 4: 左臂内顶点（底面）
    append verts (rightTopInner - [0,0,halfThick])         -- 5: 右臂内顶点（底面）
    append verts (rightTopOuter - [0,0,halfThick])         -- 6: 右臂外顶点（底面）
    append verts (rightBottomOuter - [0,0,halfThick])      -- 7: 右臂外底点（底面）
    
    -- 创建顶面顶点
    append verts (weldedBottomInner + [0,0,halfThick])      -- 8: 焊接的内侧底点（顶面）
    append verts (leftBottomOuter + [0,0,halfThick])       -- 9: 左臂外底点（顶面）
    append verts (leftTopOuter + [0,0,halfThick])          -- 10: 左臂外顶点（顶面）
    append verts (leftTopInner + [0,0,halfThick])          -- 11: 左臂内顶点（顶面）
    append verts (rightTopInner + [0,0,halfThick])         -- 12: 右臂内顶点（顶面）
    append verts (rightTopOuter + [0,0,halfThick])         -- 13: 右臂外顶点（顶面）
    append verts (rightBottomOuter + [0,0,halfThick])      -- 14: 右臂外底点（顶面）
    
    -- 创建底面（以共享中心点为中心的扇形面）
    append faces [1,2,3]    -- 左臂外侧三角形
    append faces [1,3,4]    -- 左臂内侧三角形
    append faces [1,4,5]    -- 中间连接三角形
    append faces [1,5,6]    -- 右臂内侧三角形
    append faces [1,6,7]    -- 右臂外侧三角形
    
    -- 创建顶面（以共享中心点为中心的扇形面）
    append faces [8,10,9]   -- 左臂外侧三角形
    append faces [8,11,10]  -- 左臂内侧三角形
    append faces [8,12,11]  -- 中间连接三角形
    append faces [8,13,12]  -- 右臂内侧三角形
    append faces [8,14,13]  -- 右臂外侧三角形
    
    -- 创建侧面
    -- 左臂外侧
    append faces [2,9,10]; append faces [2,10,3]
    -- 左臂顶端
    append faces [3,10,11]; append faces [3,11,4]
    -- 左臂内侧
    append faces [4,11,8]; append faces [4,8,1]
    -- 右臂内侧
    append faces [1,8,12]; append faces [1,12,5]
    -- 右臂顶端
    append faces [5,12,13]; append faces [5,13,6]
    -- 右臂外侧
    append faces [6,13,14]; append faces [6,14,7]
    -- 右臂底部
    append faces [7,14,8]; append faces [7,8,1]
    -- 左臂底部
    append faces [1,8,9]; append faces [1,9,2]
    
    return #(verts, faces)
)

-------
-- 计算导流线V字形位置
-------
fn calculateVShapePositions spline1 spline2 vLen vSpacing direction =
(
    local result = #()
    local centerPoints = calculateCenterPath spline1 spline2
    
    if centerPoints.count > 1 then
    (
        -- 计算中心路径的总长度
        local totalLength = 0
        for i = 2 to centerPoints.count do
        (
            totalLength += distance centerPoints[i-1] centerPoints[i]
        )
        
        if totalLength > vLen then
        (
            -- 计算V字形数量和起始位置
            local numVShapes = (totalLength / vSpacing) as integer
            local startOffset = (totalLength - (numVShapes - 1) * vSpacing) / 2.0
            
            -- 生成V字形位置
            for vIdx = 1 to numVShapes do
            (
                local targetDist = startOffset + (vIdx - 1) * vSpacing
                local currentDist = 0
                
                -- 在中心路径上找到对应位置
                for i = 2 to centerPoints.count do
                (
                    local segmentLength = distance centerPoints[i-1] centerPoints[i]
                    
                    if currentDist + segmentLength >= targetDist then
                    (
                        -- 在这个线段上插值
                        local segmentParam = (targetDist - currentDist) / segmentLength
                        local vPos = centerPoints[i-1] + (centerPoints[i] - centerPoints[i-1]) * segmentParam
                        
                        -- 计算V字形方向
                        local vDir = normalize (centerPoints[i] - centerPoints[i-1])
                        if direction < 0 then vDir = -vDir
                        
                        -- 计算路径参数以获取实际边界点
                        local pathParam = targetDist / totalLength
                        local leftBoundary = lengthInterp spline1 1 pathParam
                        local rightBoundary = lengthInterp spline2 1 pathParam
                        
                        append result #(vPos, vDir, leftBoundary, rightBoundary)
                        exit
                    )
                    
                    currentDist += segmentLength
                )
            )
        )
    )
    
    return result
)

-------
-- 预览绘制函数
-------
fn drawTrafficGuidePreview splines vLen vWidth vSpacing lineThick direction =
(
    if splines.count >= 2 then
    (
        gw.setTransform(matrix3 1)
        gw.setColor #line tgl_previewColor
        
        local spline1 = splines[1]
        local spline2 = splines[2]
        
        -- 绘制中心路径（调试用）
        local centerPoints = calculateCenterPath spline1 spline2
        if centerPoints.count > 1 then
        (
            gw.setColor #line (color 100 100 100)  -- 灰色中心线
            for i = 2 to centerPoints.count do
            (
                gw.polyline #(centerPoints[i-1], centerPoints[i]) false
            )
        )
        
        -- 计算并绘制V字形位置
        local vPositions = calculateVShapePositions spline1 spline2 vLen vSpacing direction
        
        gw.setColor #line tgl_previewColor
        for vData in vPositions do
        (
            local vPos = vData[1]
            local vDir = vData[2]
            local leftBoundary = vData[3]
            local rightBoundary = vData[4]
            
            -- 计算V字形的实际宽度边界进行线框预览
            local halfLength = vLen / 2.0
            local lineWidth = lineThick * 0.8  -- V字线条的宽度
            local halfLineWidth = lineWidth / 2.0
            
            -- V字形的关键点
            local centerBottom = vPos - vDir * halfLength
            local topPos = vPos + vDir * halfLength
            local leftTop = leftBoundary + (topPos.z - leftBoundary.z) * [0,0,1]
            local rightTop = rightBoundary + (topPos.z - rightBoundary.z) * [0,0,1]
            
            -- 计算左臂和右臂的方向向量和垂直向量
            local leftArmDir = normalize (leftTop - centerBottom)
            local leftArmPerp = normalize (cross leftArmDir [0,0,1])
            local rightArmDir = normalize (rightTop - centerBottom)
            local rightArmPerp = normalize (cross rightArmDir [0,0,1])
            
            -- 计算左臂的四个边界点
            local leftArm_p1 = centerBottom - leftArmPerp * halfLineWidth
            local leftArm_p2 = centerBottom + leftArmPerp * halfLineWidth
            local leftArm_p3 = leftTop + leftArmPerp * halfLineWidth
            local leftArm_p4 = leftTop - leftArmPerp * halfLineWidth
            
            -- 计算右臂的四个边界点
            local rightArm_p1 = centerBottom - rightArmPerp * halfLineWidth
            local rightArm_p2 = centerBottom + rightArmPerp * halfLineWidth
            local rightArm_p3 = rightTop + rightArmPerp * halfLineWidth
            local rightArm_p4 = rightTop - rightArmPerp * halfLineWidth
            
            -- 绘制左臂线框轮廓
            gw.polyline #(leftArm_p1, leftArm_p2, leftArm_p3, leftArm_p4, leftArm_p1) false
            
            -- 绘制右臂线框轮廓
            gw.polyline #(rightArm_p1, rightArm_p2, rightArm_p3, rightArm_p4, rightArm_p1) false
            
            -- 绘制V字形中心轮廓线（可选，用于更清晰地显示V字形状）
            gw.setColor #line (color 200 200 0)  -- 稍暗的黄色
            gw.polyline #(leftTop, centerBottom, rightTop) false
            gw.setColor #line tgl_previewColor  -- 恢复原色
        )
        
        gw.enlargeUpdateRect #whole
        gw.updateScreen()
    )
)

-------
-- 生成导流线几何体
-------
fn generateTrafficGuideLine splines vLen vSpacing lineThick direction =
(
    if splines.count < 2 then
    (
        messageBox "请选择两条样条线！" title:"错误"
        return undefined
    )
    
    local spline1 = splines[1]
    local spline2 = splines[2]
    
    -- 计算V字形位置
    local vPositions = calculateVShapePositions spline1 spline2 vLen vSpacing direction
    
    if vPositions.count == 0 then
    (
        messageBox "无法生成V字形，请检查样条线长度和参数设置！" title:"警告"
        return undefined
    )
    
    -- 合并所有V字形几何体
    local allVerts = #()
    local allFaces = #()
    local vertOffset = 0
    
    for vData in vPositions do
    (
        local vPos = vData[1]
        local vDir = vData[2]
        local leftBoundary = vData[3]
        local rightBoundary = vData[4]
        
        -- 创建单个V字形几何体
        local vGeom = createVShapeGeometry vPos vDir leftBoundary rightBoundary vLen lineThick
        local verts = vGeom[1]
        local faces = vGeom[2]
        
        -- 添加顶点
        for v in verts do
            append allVerts v
        
        -- 添加面（调整顶点索引）
        for f in faces do
        (
            local newFace = [f[1] + vertOffset, f[2] + vertOffset, f[3] + vertOffset]
            append allFaces newFace
        )
        
        vertOffset += verts.count
    )
    
    -- 创建网格对象
    if allVerts.count > 0 and allFaces.count > 0 then
    (
        local meshObj = mesh vertices:allVerts faces:allFaces
        meshObj.name = "TrafficGuideLine_" + (spline1.name as string) + "_" + (spline2.name as string)
        
        -- 转换为可编辑多边形
        convertToMesh meshObj
        
        return meshObj
    )
    
    return undefined
)

-------
-- 预览系统
-------
fn initTrafficGuidePreview =
(
    try
    (
        if tgl_previewEnabled and tgl_selectedSplines.count >= 2 then
        (
            drawTrafficGuidePreview tgl_selectedSplines tgl_vLength tgl_vWidth tgl_vSpacing tgl_lineThickness tgl_vDirection
        )
    )
    catch()
)

fn registerPreview =
(
    unregisterRedrawViewsCallback initTrafficGuidePreview
    registerRedrawViewsCallback initTrafficGuidePreview
    redrawviews()
)

fn unregisterPreview =
(
    unregisterRedrawViewsCallback initTrafficGuidePreview
    forcecompleteredraw()
)

-------
-- 用户界面
-------
try destroyDialog TrafficGuideLineRol catch()
rollout TrafficGuideLineRol "车道导流线生成器 v1.0.0" width:220 height:365
(
    groupBox 'grp1' "样条线选择" pos:[8,8] width:204 height:60 align:#left
    label 'lblInfo' "请选择两条样条线作为车道边界" pos:[15,25] width:190 height:15 align:#left
    button 'btnSelect' "选择样条线" pos:[15,40] width:100 height:25 align:#left
    label 'lblCount' "已选择: 0 条" pos:[125,45] width:80 height:15 align:#left
    
    groupBox 'grp2' "V字形参数" pos:[8,75] width:204 height:115 align:#left
    spinner 'spnVLength' "V字长度:" pos:[15,95] width:150 height:20 range:[100,2000,200] type:#worldunits scale:0.01
    spinner 'spnVSpacing' "V字间距:" pos:[15,120] width:150 height:20 range:[200,5000,200] type:#worldunits scale:0.01
    spinner 'spnLineThickness' "线条厚度:" pos:[15,145] width:150 height:20 range:[10,500,100] type:#worldunits scale:0.01
    radiobuttons 'rdoDirection' "V字方向:" pos:[15,165] width:180 height:20 labels:#("正向", "反向") default:1
    
    groupBox 'grp3' "预览和生成" pos:[8,200] width:204 height:80 align:#left
    checkbox 'chkPreview' "显示预览" pos:[15,220] width:80 height:20 align:#left
    button 'btnGenerate' "生成导流线" pos:[50,245] width:120 height:30 align:#left
    
    groupBox 'grp4' "使用说明" pos:[8,290] width:204 height:65 align:#left
    label 'lblHelp1' "1. 选择两条定义车道边界的样条线" pos:[12,305] width:195 height:12 align:#left
    label 'lblHelp2' "2. 调整V字形参数" pos:[12,317] width:195 height:12 align:#left
    label 'lblHelp3' "3. 开启预览查看效果，然后生成" pos:[12,329] width:195 height:12 align:#left
    label 'lblHelp4' "注：V字宽度自动对齐到边界样条线" pos:[12,341] width:195 height:12 align:#left
    
    -- 更新预览
    fn updatePreview =
    (
        if chkPreview.checked and tgl_selectedSplines.count >= 2 then
        (
            tgl_vLength = spnVLength.value
            tgl_vSpacing = spnVSpacing.value
            tgl_lineThickness = spnLineThickness.value
            tgl_vDirection = if rdoDirection.state == 1 then 1 else -1
            redrawviews()
        )
    )
    
    -- 界面事件
    on TrafficGuideLineRol open do
    (
        unregisterPreview()
        tgl_previewEnabled = false
        chkPreview.checked = false
        tgl_selectedSplines = #()
        lblCount.text = "已选择: 0 条"
    )
    
    on TrafficGuideLineRol close do
    (
        unregisterPreview()
        tgl_selectedSplines = #()
        tgl_previewEnabled = false
    )
    
    on btnSelect pressed do
    (
        local selectedShapes = #()
        for obj in selection do
        (
            if superclassof obj == Shape then
                append selectedShapes obj
        )
        
        if selectedShapes.count >= 2 then
        (
            tgl_selectedSplines = #(selectedShapes[1], selectedShapes[2])
            lblCount.text = "已选择: 2 条"
            if selectedShapes.count > 2 then
                messageBox ("检测到" + selectedShapes.count as string + "条样条线，将使用前两条。") title:"提示"
        )
        else
        (
            tgl_selectedSplines = #()
            lblCount.text = "已选择: 0 条"
            messageBox "请选择至少两条样条线！" title:"提示"
        )
        
        updatePreview()
    )
    
    on chkPreview changed state do
    (
        tgl_previewEnabled = state
        if state then
        (
            if tgl_selectedSplines.count >= 2 then
            (
                registerPreview()
                updatePreview()
            )
            else
            (
                messageBox "请先选择两条样条线！" title:"提示"
                chkPreview.checked = false
                tgl_previewEnabled = false
            )
        )
        else
        (
            unregisterPreview()
        )
    )
    
    on spnVLength changed val do updatePreview()
    on spnVSpacing changed val do updatePreview()
    on spnLineThickness changed val do updatePreview()
    on rdoDirection changed state do updatePreview()
    
    on btnGenerate pressed do
    (
        if tgl_selectedSplines.count < 2 then
        (
            messageBox "请先选择两条样条线！" title:"错误"
            return()
        )
        
        undo on
        (
            -- 关闭预览
            if chkPreview.checked then
            (
                chkPreview.checked = false
                tgl_previewEnabled = false
                unregisterPreview()
            )
            
            -- 生成导流线
            local result = generateTrafficGuideLine tgl_selectedSplines spnVLength.value spnVSpacing.value spnLineThickness.value (if rdoDirection.state == 1 then 1 else -1)
            
            if result != undefined then
            (
                select result
                messageBox ("成功生成导流线！\n对象名称: " + result.name) title:"完成"
            )
            else
            (
                messageBox "生成失败，请检查参数设置！" title:"错误"
            )
        )
    )
)

CreateDialog TrafficGuideLineRol