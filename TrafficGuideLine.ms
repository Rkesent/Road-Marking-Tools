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
-- 创建单个V字形平面几何体（使用中线+前后辅助线方法）
-------
fn createVShapePlane centerPos direction leftBoundary rightBoundary vLength lineThick =
(
    -- 步骤1：生成V字形中线骨骼
    local halfLength = vLength / 2.0
    local centerBottom = centerPos - direction * halfLength
    local topPos = centerPos + direction * halfLength
    
    -- 确保所有点都在同一Z平面上
    local baseZ = centerPos.z
    local leftTop = [leftBoundary.x, leftBoundary.y, baseZ]
    local rightTop = [rightBoundary.x, rightBoundary.y, baseZ]
    centerBottom = [centerBottom.x, centerBottom.y, baseZ]
    
    -- V字形中线骨骼的三个关键点
    local centerLine = #(leftTop, centerBottom, rightTop)
    
    -- 步骤2：生成前后两条辅助线（为每个点计算正确的局部切线方向）
    local halfWidth = lineThick / 2.0
    local frontLine = #()
    local backLine = #()
    
    -- 为每个中心线点计算正确的偏移方向
    for i = 1 to centerLine.count do
    (
        local currentPt = centerLine[i]
        local tangentDir
        
        if i == 1 then
        (
            -- 第一个点（leftTop）：使用到下一个点的方向
            tangentDir = normalize (centerLine[i+1] - currentPt)
        )
        else if i == centerLine.count then
        (
            -- 最后一个点（rightTop）：使用从上一个点的方向
            tangentDir = normalize (currentPt - centerLine[i-1])
        )
        else
        (
            -- 中间点（centerBottom）：使用角平分线方向
            local inDir = normalize (currentPt - centerLine[i-1])  -- 入射方向
            local outDir = normalize (centerLine[i+1] - currentPt) -- 出射方向
            tangentDir = normalize (inDir + outDir)  -- 角平分线方向
        )
        
        -- 计算垂直方向并偏移
        local perpDir = normalize (cross tangentDir [0,0,1])
        local frontPt = currentPt + perpDir * halfWidth
        local backPt = currentPt - perpDir * halfWidth
        
        append frontLine frontPt
        append backLine backPt
    )
    
    -- 步骤3：生成面片数据
    local verts = #()
    local faces = #()
    
    -- 添加所有顶点（前线 + 后线）
    for pt in frontLine do append verts pt
    for pt in backLine do append verts pt
    
    -- 生成四边形面片，连接前后两条线
    local frontCount = frontLine.count
    for i = 1 to (frontCount - 1) do
    (
        local v1 = i                    -- 前线当前点
        local v2 = i + 1                -- 前线下一点
        local v3 = frontCount + i + 1   -- 后线下一点
        local v4 = frontCount + i       -- 后线当前点
        
        -- 创建两个三角形组成四边形
        append faces [v1, v2, v3]
        append faces [v1, v3, v4]
    )
    
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
        
        -- 计算并绘制V字形位置（使用中线+前后辅助线方法）
        local vPositions = calculateVShapePositions spline1 spline2 vLen vSpacing direction
        
        gw.setColor #line tgl_previewColor
        for vData in vPositions do
        (
            local vPos = vData[1]
            local vDir = vData[2]
            local leftBoundary = vData[3]
            local rightBoundary = vData[4]
            
            -- 使用与createVShapePlane函数完全相同的逻辑
            local halfLength = vLen / 2.0
            local centerBottom = vPos - vDir * halfLength
            local topPos = vPos + vDir * halfLength
            
            -- 确保所有点都在同一Z平面上
            local baseZ = vPos.z
            local leftTop = [leftBoundary.x, leftBoundary.y, baseZ]
            local rightTop = [rightBoundary.x, rightBoundary.y, baseZ]
            centerBottom = [centerBottom.x, centerBottom.y, baseZ]
            
            -- 步骤1：生成V字形中线骨骼
            local centerLine = #(leftTop, centerBottom, rightTop)
            
            -- 步骤2：生成前后两条辅助线（为每个点计算正确的局部切线方向）
            local halfWidth = lineThick / 2.0
            local frontLine = #()
            local backLine = #()
            
            -- 为每个中心线点计算正确的偏移方向
            for i = 1 to centerLine.count do
            (
                local currentPt = centerLine[i]
                local tangentDir
                
                if i == 1 then
                (
                    -- 第一个点（leftTop）：使用到下一个点的方向
                    tangentDir = normalize (centerLine[i+1] - currentPt)
                )
                else if i == centerLine.count then
                (
                    -- 最后一个点（rightTop）：使用从上一个点的方向
                    tangentDir = normalize (currentPt - centerLine[i-1])
                )
                else
                (
                    -- 中间点（centerBottom）：使用角平分线方向
                    local inDir = normalize (currentPt - centerLine[i-1])  -- 入射方向
                    local outDir = normalize (centerLine[i+1] - currentPt) -- 出射方向
                    tangentDir = normalize (inDir + outDir)  -- 角平分线方向
                )
                
                -- 计算垂直方向并偏移
                local perpDir = normalize (cross tangentDir [0,0,1])
                local frontPt = currentPt + perpDir * halfWidth
                local backPt = currentPt - perpDir * halfWidth
                
                append frontLine frontPt
                append backLine backPt
            )
            
            -- 绘制前后辅助线
            gw.setColor #line tgl_previewColor
            gw.polyline frontLine false  -- 前辅助线
            gw.polyline backLine false   -- 后辅助线
            
            -- 绘制连接线，显示面片结构
            for i = 1 to frontLine.count do
            (
                gw.polyline #(frontLine[i], backLine[i]) false
            )
            
            -- 绘制V字形中心骨架线（用较暗的颜色作为参考）
            gw.setColor #line (color 150 150 0)  -- 较暗的黄色
            gw.polyline centerLine false
            gw.setColor #line tgl_previewColor  -- 恢复原色
        )
        
        gw.enlargeUpdateRect #whole
        gw.updateScreen()
    )
)

-------
-- 生成导流线几何体（使用偏移算法生成平面）
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
    
    -- 收集所有V字形的顶点和面
    local allVerts = #()
    local allFaces = #()
    local vertOffset = 0
    
    -- 为每个V字形位置创建平面几何体
    for vData in vPositions do
    (
        local vPos = vData[1]
        local vDir = vData[2]
        local leftBoundary = vData[3]
        local rightBoundary = vData[4]
        
        -- 创建V字形平面几何体数据
        local vGeomData = createVShapePlane vPos vDir leftBoundary rightBoundary vLen lineThick
        
        if vGeomData != undefined and vGeomData.count == 2 then
        (
            local vVerts = vGeomData[1]
            local vFaces = vGeomData[2]
            
            -- 添加顶点到总数组
            for v in vVerts do
                append allVerts v
            
            -- 添加面片（调整顶点索引）
            for f in vFaces do
            (
                local newFace = [f[1] + vertOffset, f[2] + vertOffset, f[3] + vertOffset]
                append allFaces newFace
            )
            
            vertOffset += vVerts.count
        )
    )
    
    -- 创建最终的网格对象
    if allVerts.count > 0 and allFaces.count > 0 then
    (
        local meshObj = mesh vertices:allVerts faces:allFaces
        meshObj.name = "TrafficGuideLine_" + (spline1.name as string) + "_" + (spline2.name as string)
        
        -- 转换为可编辑多边形
        convertToMesh meshObj
        
        messageBox ("成功生成 " + vPositions.count as string + " 个V字形导流线！") title:"完成"
        
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