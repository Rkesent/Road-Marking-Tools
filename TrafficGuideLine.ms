-------
-- TrafficGuideLine v1.0.0 - 车道导流线生成器
-- 功能：基于两条样条线生成V字形导流线标记
-------

-- 清除之前的函数定义以避免冲突
try (analyzeSplineIntersection = undefined) catch()
try (calculateBoundaryPoint = undefined) catch()

-- Loading TrafficGuideLine script

-- 全局变量
global tgl_previewColor = color 255 255 0  -- 黄色预览线条
global tgl_selectedSplines = #()
global tgl_previewEnabled = false
global tgl_vSpacing = 200        -- V字形间距 (mm)
global tgl_lineThickness = 100    -- 线条粗细 (mm)
global tgl_vDirection = 1         -- V字形方向 (1=正向, -1=反向)
global tgl_standardVAngle = 60.0     -- 标准开合角度 (度)
global tgl_offsetDistance = 500.0   -- 向后偏移距离 (mm)

-------
-- 计算边界点（约束在边界线上）
-- 参数：
--   centerPos: V字形中心点位置
--   pathDirection: 路径方向向量
--   boundarySpline: 边界样条线
--   fixedAngle: 固定角度（度）
--   isLeft: 是否为左侧边界点
-- 返回：约束在边界线上的边界点
-------
fn calculateBoundaryPoint centerPos pathDirection boundarySpline fixedAngle isLeft =
(
    try
    (
        -- 计算V字形的半角（弧度）
        local halfAngleRad = degToRad (fixedAngle / 2.0)
        
        -- 计算前进方向的单位向量
        local forwardDir = normalize pathDirection
        
        -- 计算V字形臂的方向
        local armAngleRad = if isLeft then -halfAngleRad else halfAngleRad
        local armDir = [forwardDir.x * cos armAngleRad - forwardDir.y * sin armAngleRad,
                       forwardDir.x * sin armAngleRad + forwardDir.y * cos armAngleRad,
                       0]
        
        -- 从中心点沿臂方向发射射线，寻找与边界样条线的交点
        local maxDistance = 1000.0  -- 最大搜索距离
        local stepSize = 1.0        -- 步长
        local closestPoint = centerPos
        local minDistance = maxDistance
        
        -- 沿射线方向搜索最近的边界点
        for i = 1 to (maxDistance / stepSize) do
        (
            local testPoint = centerPos + armDir * (i * stepSize)
            
            -- 使用参数化投影方法计算测试点到样条线的最近点
            local splinePoint = findClosestPointOnSplineParametric boundarySpline testPoint
            local distance = distance testPoint splinePoint
            
            -- 如果找到更近的点，更新结果
            if distance < minDistance then
            (
                minDistance = distance
                closestPoint = splinePoint
            )
            
            -- 如果距离开始增大，说明已经过了最近点
            if i > 10 and distance > minDistance * 2 then
                exit
        )
        
        return closestPoint
    )
    catch
    (
        -- 如果计算失败，返回中心点
        return centerPos
    )
)

-------
-- 创建标准V字形几何体
-- 参数：
--   centerPos: V字形中心点位置
--   pathDirection: 路径方向向量
--   lineThickness: 线条厚度
--   leftBoundary: 左侧边界点（已约束在边界线上）
--   rightBoundary: 右侧边界点（已约束在边界线上）
-- 返回：V字形网格对象
-------
fn createStandardVShape centerPos pathDirection lineThickness leftBoundary rightBoundary =
(
    try
    (
        -- 使用传入的边界点作为V字形端点
        local leftEnd = leftBoundary
        local rightEnd = rightBoundary
        local vWidth = if lineThickness != undefined then lineThickness else 2.0
        
        -- 确保所有点在同一水平面上
        leftEnd.z = centerPos.z
        rightEnd.z = centerPos.z
        
        -- 计算线条宽度的一半
        local halfWidth = vWidth / 2.0
        
        -- 创建V字形几何体
        local verts = #()
        local faces = #()
        
        -- 计算V字形的顶点（考虑线条宽度）
        -- 左臂方向和垂直方向
        local leftArmDir = normalize (leftEnd - centerPos)
        local leftPerpDir = normalize (cross leftArmDir [0,0,1])
        
        -- 右臂方向和垂直方向
        local rightArmDir = normalize (rightEnd - centerPos)
        local rightPerpDir = normalize (cross rightArmDir [0,0,1])
        
        -- 左臂的四个顶点
        append verts (centerPos + leftPerpDir * halfWidth)     -- 1: 左臂内侧底部
        append verts (centerPos - leftPerpDir * halfWidth)     -- 2: 左臂外侧底部
        append verts (leftEnd + leftPerpDir * halfWidth)       -- 3: 左臂内侧顶部
        append verts (leftEnd - leftPerpDir * halfWidth)       -- 4: 左臂外侧顶部
        
        -- 右臂的四个顶点
        append verts (centerPos - rightPerpDir * halfWidth)    -- 5: 右臂内侧底部
        append verts (centerPos + rightPerpDir * halfWidth)    -- 6: 右臂外侧底部
        append verts (rightEnd - rightPerpDir * halfWidth)     -- 7: 右臂内侧顶部
        append verts (rightEnd + rightPerpDir * halfWidth)     -- 8: 右臂外侧顶部
        
        -- 创建面（三角形）
        -- 左臂的面
        append faces [1, 2, 3]  -- 左臂底部三角形1
        append faces [2, 4, 3]  -- 左臂底部三角形2
        
        -- 右臂的面
        append faces [5, 6, 7]  -- 右臂底部三角形1
        append faces [6, 8, 7]  -- 右臂底部三角形2
        
        -- 创建mesh对象
        local vMesh = mesh vertices:verts faces:faces
        vMesh.name = "StandardVShape_" + (random 1000 9999) as string
        
        -- 设置材质ID
        for i = 1 to vMesh.numfaces do
        (
            setFaceMatID vMesh i 1
        )
        
        -- 移动到指定位置
        vMesh.pos = centerPos
        
        -- 根据方向旋转
        if direction != undefined then
        (
            local dirAngle = atan2 direction.y direction.x
            rotate vMesh (angleaxis (radToDeg dirAngle) [0,0,1])
        )
        
        update vMesh
        return vMesh
    )
    catch
    (
        print ("createStandardVShape 错误: " + getCurrentException())
        return undefined
    )
)

-------
-- 核心算法：计算两条样条线之间的中心路径（改进版）
-------
fn calculateCenterPathAdaptive spline1 spline2 targetSegmentLength:10.0 minSamples:20 maxSamples:100 =
(
    local centerPoints = #()
    local spline1Length = curveLength spline1 1
    local spline2Length = curveLength spline2 1
    local maxLength = amax spline1Length spline2Length
    
    if maxLength > 0 then
    (
        -- 根据路径长度自适应计算采样点数量
        local adaptiveSampleCount = (maxLength / targetSegmentLength) as integer
        adaptiveSampleCount = amax minSamples (amin maxSamples adaptiveSampleCount)
        
        for i = 0 to adaptiveSampleCount do
        (
            local param = i as float / adaptiveSampleCount as float
            
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
-- 向后兼容的中心路径计算函数
-------
fn calculateCenterPath spline1 spline2 =
(
    -- 使用改进的自适应算法，但保持原有的默认行为
    return calculateCenterPathAdaptive spline1 spline2 targetSegmentLength:10.0 minSamples:50 maxSamples:50
)

-------
-- 辅助函数：查找样条线上最近的点
-------
fn findClosestPointOnSplineParametric splineObj targetPoint tolerance:0.001 maxIterations:20 =
(
    local bestParam = 0.5  -- 初始参数值
    local bestPoint = lengthInterp splineObj 1 bestParam
    local bestDist = distance targetPoint bestPoint
    
    -- 使用二分搜索优化的参数化投影方法
    local searchRange = 1.0  -- 搜索范围
    local searchCenter = 0.5  -- 搜索中心
    
    for iteration = 1 to maxIterations do
    (
        local stepSize = searchRange / 4.0
        local improved = false
        
        -- 在当前搜索范围内测试多个点
        for testOffset in #(-stepSize, 0, stepSize) do
        (
            local testParam = searchCenter + testOffset
            
            -- 确保参数在有效范围内
            if testParam >= 0.0 and testParam <= 1.0 then
            (
                local testPoint = lengthInterp splineObj 1 testParam
                local testDist = distance targetPoint testPoint
                
                if testDist < bestDist then
                (
                    bestDist = testDist
                    bestParam = testParam
                    bestPoint = testPoint
                    searchCenter = testParam
                    improved = true
                )
            )
        )
        
        -- 缩小搜索范围
        searchRange *= 0.5
        
        -- 如果距离足够小或没有改进，提前退出
        if bestDist < tolerance or not improved then
            exit
    )
    
    return bestPoint
)

-------
-- 向后兼容的包装函数
-------
fn findClosestPointOnSpline splineObj targetPoint =
(
    return findClosestPointOnSplineParametric splineObj targetPoint
)

-------
-- 检测两条样条线的起始点是否重合，并计算封闭信息
-------
fn analyzeSplineIntersection spline1 spline2 =
(
    local intersectionTolerance = 50.0  -- 相交判定容差（系统单位）
    
    -- 获取两条样条线的起始点
    local spline1Start = lengthInterp spline1 1 0.0  -- 样条线1的起始点
    local spline2Start = lengthInterp spline2 1 0.0  -- 样条线2的起始点
    
    -- 检查起始点是否重合
    local startIntersect = (distance spline1Start spline2Start) < intersectionTolerance
    
    -- 返回结果：#(起始点重合状态, 封闭线段数据)
    local startClosureLine = undefined
    
    -- 只有在起始点未重合时才创建封闭线段
    if not startIntersect then
        startClosureLine = #(spline1Start, spline2Start)
    
    return #(startIntersect, startClosureLine)
)

-------
-- 创建封闭线段的3D模型（基于analyzeSplineIntersection结果向后扩展）
-- 参数：
--   startPoint: 原始封闭线段起点
--   endPoint: 原始封闭线段终点  
--   lineThickness: 线条厚度
--   spline1: 第一条样条线（用于计算后方向）
--   spline2: 第二条样条线（用于计算后方向）
--   extensionDistance: 向后扩展的距离
-- 返回：扩展后的封闭线段网格数组
-------
fn createClosureLine startPoint endPoint lineThickness spline1 spline2 extensionDistance =
(
    try
    (
        if startPoint == undefined or endPoint == undefined then
            return #()
            
        -- 计算原始线段方向和长度
        local lineVector = endPoint - startPoint
        local lineLength = length lineVector
        
        if lineLength < 1.0 then  -- 太短的线段跳过
            return #()
        
        -- 计算两条样条线的整体方向（从首点到尾点）
        local spline1Start = lengthInterp spline1 1 0.0
        local spline1End = lengthInterp spline1 1 1.0
        local spline2Start = lengthInterp spline2 1 0.0
        local spline2End = lengthInterp spline2 1 1.0
        
        -- 计算每条样条线的方向向量
        local spline1Dir = normalize (spline1End - spline1Start)
        local spline2Dir = normalize (spline2End - spline2Start)
        
        -- 计算平均方向作为"后方向"（模型整体后方向）
        local backwardDirection = normalize (spline1Dir + spline2Dir)
        
        local createdMeshes = #()
        
        -- 创建原始封闭线段
        local originalMesh = createSingleClosureLine startPoint endPoint lineThickness "ClosureLine"
        if originalMesh != undefined then
            append createdMeshes originalMesh
        
        -- 如果指定了扩展距离，创建在中心线上向后偏移的线段
        if extensionDistance != undefined and extensionDistance > 0 then
        (
            -- 计算两条样条线的整体方向（从首点到尾点）
            local spline1StartPt = lengthInterp spline1 1 0.0
            local spline1EndPt = lengthInterp spline1 1 1.0
            local spline2StartPt = lengthInterp spline2 1 0.0
            local spline2EndPt = lengthInterp spline2 1 1.0
            
            local spline1Dir = normalize (spline1EndPt - spline1StartPt)
            local spline2Dir = normalize (spline2EndPt - spline2StartPt)
            local backwardDirection = normalize (spline1Dir + spline2Dir)
            
            -- 使用参数化方法计算偏移点（类似V字距离的数学映射）
            local spline1Length = curveLength spline1 1
            local spline2Length = curveLength spline2 1
            
            -- 将扩展距离转换为样条线参数
            local offsetParam1 = if spline1Length > 0 then (extensionDistance / spline1Length) else 0.0
            local offsetParam2 = if spline2Length > 0 then (extensionDistance / spline2Length) else 0.0
            
            -- 确保参数在有效范围内
            offsetParam1 = amax 0.0 (amin 1.0 offsetParam1)
            offsetParam2 = amax 0.0 (amin 1.0 offsetParam2)
            
            -- 直接使用lengthInterp获取精确的偏移点
            local projectedStart = lengthInterp spline1 1 offsetParam1
            local projectedEnd = lengthInterp spline2 1 offsetParam2
            
            -- 创建中心偏移线段
            local extendedMesh = createSingleClosureLine projectedStart projectedEnd lineThickness "CenterOffsetLine"
            if extendedMesh != undefined then
                append createdMeshes extendedMesh
        )
        
        return createdMeshes
    )
    catch
    (
        print ("createClosureLine 错误: " + getCurrentException())
        return #()
    )
)

-------
-- 创建单条封闭线段的3D模型（内部辅助函数）
-------
fn createSingleClosureLine startPoint endPoint lineThickness meshName =
(
    try
    (
        local lineVector = endPoint - startPoint
        local lineLength = length lineVector
        
        if lineLength < 1.0 then
            return undefined
        
        local lineDir = normalize lineVector
        local halfThickness = lineThickness / 2.0
        
        -- 计算垂直于线段的方向（在XY平面上）
        local perpDir = normalize (cross [0,0,1] lineDir)
        
        -- 创建矩形的四个顶点（逆时针顺序）
        local verts = #()
        append verts (startPoint + perpDir * halfThickness)
        append verts (startPoint - perpDir * halfThickness)
        append verts (endPoint - perpDir * halfThickness)
        append verts (endPoint + perpDir * halfThickness)
        
        -- 创建面（确保正确的面向）
        local faces = #()
        append faces [1,2,3]
        append faces [3,4,1]
        
        -- 创建mesh对象
        local newMesh = mesh vertices:verts faces:faces
        newMesh.name = meshName + "_" + (random 1000 9999) as string
        
        -- 设置材质ID
        for i = 1 to newMesh.numfaces do
        (
            setFaceMatID newMesh i 1
        )
        
        update newMesh
        return newMesh
    )
    catch
    (
        print ("createSingleClosureLine 错误: " + getCurrentException())
        return undefined
    )
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
-- 计算V字形中心开合角度
-------
fn calculateVShapeAngle leftBoundary rightBoundary centerBottom =
(
    -- 计算从中心底部到左右边界的向量
    local leftVector = normalize (leftBoundary - centerBottom)
    local rightVector = normalize (rightBoundary - centerBottom)
    
    -- 计算两个向量之间的夹角（弧度）
    local dotProduct = dot leftVector rightVector
    -- 限制点积值在有效范围内，避免数值误差
    dotProduct = amax -1.0 (amin 1.0 dotProduct)
    local angleRadians = acos dotProduct
    
    -- 转换为度数
    local angleDegrees = radToDeg angleRadians
    
    return angleDegrees
)


-------
-- 重新实现的中心模型生成算法
-------
-- 创建V字形导流线的3D网格模型
-- 参数：
--   vPos: V字形中心位置
--   vDir: V字形方向向量
--   leftBoundary: 左侧边界点
--   rightBoundary: 右侧边界点
--   leftSpline: 左侧边界样条线
--   rightSpline: 右侧边界样条线
--   lineThickness: 线条厚度
--   direction: 方向系数
--   fixedAngle: 固定角度
-- 返回：V字形网格对象
-------
fn createVShapeModel vPos vDir leftBoundary rightBoundary leftSpline rightSpline lineThickness direction fixedAngle = 
(
	try
	(
		-- 检查参数有效性
		if vPos == undefined or vDir == undefined then
		(
			print "createVShapeModel: 参数无效"
			return undefined
		)
		
		-- 固定中心模型：使用标准V字形，边界点约束在边界线上
        local pathDirection = if vDir != undefined then vDir else [1,0,0]
        pathDirection = pathDirection * direction  -- 应用方向系数
        
        -- 使用传入的边界点（已约束在边界线上）
        -- leftBoundary 和 rightBoundary 已经通过参数传入
        
        local standardVShape = createStandardVShape vPos pathDirection lineThickness leftBoundary rightBoundary
        return standardVShape
	)
	catch
	(
		print ("createVShapeModel 错误: " + getCurrentException())
		return undefined
	)
)

-------
-- 计算V字形位置和方向
-- 参数：
--   spline1: 第一条边界样条线
--   spline2: 第二条边界样条线
--   vSpacing: V字形间距
--   direction: 方向系数（1或-1）
--   fixedAngle: 固定角度（度）
-- 返回：包含位置、方向和边界点的数组
-------
fn calculateVShapePositions spline1 spline2 vSpacing direction fixedAngle =
(
    local result = #()
    local centerPoints = calculateCenterPath spline1 spline2
    
    -- 分析样条线起始点重合情况
    local intersectionInfo = analyzeSplineIntersection spline1 spline2
    local startIntersect = intersectionInfo[1]  -- 起始点是否重合
    
    if centerPoints.count > 1 then
    (
        -- 计算中心路径的总长度
        local totalLength = 0
        for i = 2 to centerPoints.count do
        (
            totalLength += distance centerPoints[i-1] centerPoints[i]
        )
        
        if totalLength > 0 then
        (
            -- 计算需要避开的封闭区域长度
            local closureBuffer = vSpacing * 0.5  -- 封闭区域缓冲距离
            
            -- 统一逻辑：无论起始点是否重合，都设置缓冲区域（不生成第一个中心模型）
            local startOffset = closureBuffer  -- 统一避让策略，从第二个位置开始生成
            
            -- 有效的V字形生成区域（从起始点算起）
            local validStartDist = startOffset
            local validEndDist = totalLength  -- 简化：不再考虑尾点缓冲
            local validLength = validEndDist - validStartDist
            
            if validLength > vSpacing then
            (
                -- 直接使用用户设置的间距值
                local actualSpacing = vSpacing
                
                -- 计算V字形数量（在有效区域内）
                local numVShapes = (validLength / actualSpacing) as integer
                
                -- 生成V字形位置（从有效起点开始）
                for vIdx = 1 to numVShapes do
                (
                    local targetDist = validStartDist + (vIdx - 1) * actualSpacing
                    
                    -- 确保在有效区域内
                    if targetDist >= validStartDist and targetDist <= validEndDist then
                    (
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
                                
                                append result #(vPos, vDir, leftBoundary, rightBoundary, fixedAngle)
                                exit
                            )
                            
                            currentDist += segmentLength
                        )
                    )
                )
            )
        )
    )
    
    return result
)

-------
-- 预览绘制函数（包含封闭线段和固定角度模式）
-------
fn drawTrafficGuidePreview splines vSpacing lineThick direction fixedAngle offsetDistance =
(
    if splines.count >= 2 then
    (
        gw.setTransform(matrix3 1)
        gw.setColor #line tgl_previewColor
        
        local spline1 = splines[1]
        local spline2 = splines[2]
        
        -- 分析起始点重合情况
        local intersectionInfo = analyzeSplineIntersection spline1 spline2
        local startIntersect = intersectionInfo[1]
        local startClosureLine = intersectionInfo[2]
        
        -- 绘制封闭线段（仅在起始点未重合时）
        if startClosureLine != undefined then
        (
            -- 绘制原始封闭线段
            gw.setColor #line (color 0 255 255)  -- 青色封闭线
            gw.polyline #(startClosureLine[1], startClosureLine[2]) false
            
            -- 绘制中心偏移线段（沿中心线向后偏移）
            if offsetDistance > 0 then
            (
                -- 计算两条样条线的整体方向
                local spline1StartPt = lengthInterp spline1 1 0.0
                local spline1EndPt = lengthInterp spline1 1 1.0
                local spline2StartPt = lengthInterp spline2 1 0.0
                local spline2EndPt = lengthInterp spline2 1 1.0
                
                local spline1Dir = normalize (spline1EndPt - spline1StartPt)
                local spline2Dir = normalize (spline2EndPt - spline2StartPt)
                local backwardDirection = normalize (spline1Dir + spline2Dir)
                
                -- 使用参数化方法计算偏移点（类似V字距离的数学映射）
                local spline1Length = curveLength spline1 1
                local spline2Length = curveLength spline2 1
                
                -- 将偏移距离转换为样条线参数
                local offsetParam1 = if spline1Length > 0 then (offsetDistance / spline1Length) else 0.0
                local offsetParam2 = if spline2Length > 0 then (offsetDistance / spline2Length) else 0.0
                
                -- 确保参数在有效范围内
                offsetParam1 = amax 0.0 (amin 1.0 offsetParam1)
                offsetParam2 = amax 0.0 (amin 1.0 offsetParam2)
                
                -- 直接使用lengthInterp获取精确的偏移点
                local projectedStart = lengthInterp spline1 1 offsetParam1
                local projectedEnd = lengthInterp spline2 1 offsetParam2
                
                gw.setColor #line (color 255 0 0)  -- 红色中心偏移线段
                gw.polyline #(projectedStart, projectedEnd) false
            )
        )
        
        -- 绘制中心路径（调试用）
        local centerPoints = calculateCenterPath spline1 spline2
        if centerPoints.count > 1 then
        (
            gw.setColor #line (color 100 100 100)  -- 灰色中心线
            for i = 2 to centerPoints.count do
            (
                gw.polyline #(centerPoints[i-1], centerPoints[i]) false
            )
            
            -- 绘制样条线采样点（黄色×标记）
            gw.setColor #line (color 255 255 0)  -- 黄色采样点
            local markerSize = 5.0  -- ×标记大小
            
            -- 显示样条线1的采样点
            for i = 0 to 50 do
            (
                local param = i / 50.0
                local pt = lengthInterp spline1 1 param
                -- 绘制×标记
                gw.polyline #([pt.x - markerSize, pt.y - markerSize, pt.z], [pt.x + markerSize, pt.y + markerSize, pt.z]) false
                gw.polyline #([pt.x + markerSize, pt.y - markerSize, pt.z], [pt.x - markerSize, pt.y + markerSize, pt.z]) false
            )
            
            -- 显示样条线2的采样点
            for i = 0 to 50 do
            (
                local param = i / 50.0
                local pt = lengthInterp spline2 1 param
                -- 绘制×标记
                gw.polyline #([pt.x - markerSize, pt.y - markerSize, pt.z], [pt.x + markerSize, pt.y + markerSize, pt.z]) false
                gw.polyline #([pt.x + markerSize, pt.y - markerSize, pt.z], [pt.x - markerSize, pt.y + markerSize, pt.z]) false
            )
        )
        
        -- 计算并绘制V字形位置点
        local vPositions = calculateVShapePositions spline1 spline2 vSpacing direction fixedAngle
        
        gw.setColor #line tgl_previewColor
        for vData in vPositions do
        (
            local vPos = vData[1]
            local vDir = vData[2]
            local leftBoundary = vData[3]
            local rightBoundary = vData[4]
            local vAngle = vData[5]
            
            -- 计算路径参数（用于边界检查）
            local totalLength = 0
            for j = 2 to centerPoints.count do
            (
                totalLength += distance centerPoints[j-1] centerPoints[j]
            )
            local pathParam = if totalLength > 0 then (distance centerPoints[1] vPos) / totalLength else 0.0
            
            -- 固定中心模型：计算标准V字形几何
            local centerLine = vPos
            local pathDirection = if vDir != undefined then vDir else [1,0,0]
            pathDirection = pathDirection * direction
            
            -- 计算标准V字形的端点用于预览
            local halfAngleRad = degToRad (vAngle / 2.0)
            
            -- 计算相对于路径方向的左右端点
            local forwardDir = normalize pathDirection
            
            -- 使用边界点作为V字形端点（已约束在边界线上）
            local centerBottom = centerLine
            local leftTop = leftBoundary
            local rightTop = rightBoundary
            
            -- 简化预览：只绘制V字形的基本轮廓（使用调整后的边界点）
            local baseZ = centerBottom.z
            local leftTopPreview = [leftTop.x, leftTop.y, baseZ]
            local rightTopPreview = [rightTop.x, rightTop.y, baseZ]
            local centerBottomPreview = [centerBottom.x, centerBottom.y, baseZ]
            
            -- 绘制V字形中心骨架线
            gw.setColor #line tgl_previewColor
            gw.polyline #(leftTopPreview, centerBottomPreview, rightTopPreview) false
            
            -- 在V字形位置绘制一个小圆点标记
            gw.setColor #line (color 255 0 0)  -- 红色标记点
            local markerSize = 10.0
            gw.polyline #([centerBottom.x - markerSize, centerBottom.y, centerBottom.z], [centerBottom.x + markerSize, centerBottom.y, centerBottom.z]) false
            gw.polyline #([centerBottom.x, centerBottom.y - markerSize, centerBottom.z], [centerBottom.x, centerBottom.y + markerSize, centerBottom.z]) false
        )
        
        gw.enlargeUpdateRect #whole
        gw.updateScreen()
    )
)

-------
-- 生成导流线几何体（包含封闭线段）
-- 参数：
--   splines: 样条线数组（至少包含两条边界样条线）
--   vSpacing: V字形间距
--   lineThick: 线条厚度
--   direction: 方向系数（1或-1）
--   fixedAngle: 固定角度（度）
-- 返回：生成的导流线组对象
-------
fn generateTrafficGuideLine splines vSpacing lineThick direction fixedAngle =
(
    if splines.count < 2 then
    (
        messageBox "请选择两条样条线！" title:"错误"
        return undefined
    )
    
    local spline1 = splines[1]
    local spline2 = splines[2]
    
    -- 分析起始点重合情况
    local intersectionInfo = analyzeSplineIntersection spline1 spline2
    local startIntersect = intersectionInfo[1]
    local startClosureLine = intersectionInfo[2]
    
    -- 计算V字形位置
        local vPositions = calculateVShapePositions spline1 spline2 vSpacing direction fixedAngle
    
    try
    (
        -- 创建组来管理所有对象
        local mainGroup = group name:("TrafficGuideLine_" + (random 1000 9999) as string)
        local createdObjects = #()
        
        -- 创建封闭线段（仅在起始点未重合时）
        if startClosureLine != undefined then
        (
            -- 使用新的createClosureLine函数，传入样条线和扩展距离
            local closureMeshes = createClosureLine startClosureLine[1] startClosureLine[2] lineThick spline1 spline2 tgl_offsetDistance
            
            -- 将所有创建的网格添加到对象集合中
            for mesh in closureMeshes do
            (
                if mesh != undefined then
                    append createdObjects mesh
            )
        )
        
        -- 创建V字形模型
        for i = 1 to vPositions.count do
        (
            local vData = vPositions[i]
            local vPos = vData[1]
            local vDir = vData[2]  
            local leftBoundary = vData[3]
            local rightBoundary = vData[4]
            local vAngle = vData[5]
            
            -- 计算路径参数（用于边界检查）
            local totalLength = 0
            local centerPoints = calculateCenterPath spline1 spline2
            for j = 2 to centerPoints.count do
            (
                totalLength += distance centerPoints[j-1] centerPoints[j]
            )
            local pathParam = if totalLength > 0 then (distance centerPoints[1] vPos) / totalLength else 0.0
            
            -- 创建单个V字形模型
            local vShapeMesh = createVShapeModel vPos vDir leftBoundary rightBoundary spline1 spline2 lineThick direction vAngle
            
            if vShapeMesh != undefined then
            (
                append createdObjects vShapeMesh
            )
        )
        
        -- 如果成功创建了模型，将它们加入组
        if createdObjects.count > 0 then
        (
            for obj in createdObjects do
            (
                obj.parent = mainGroup
            )
            
            -- 设置组的颜色
            mainGroup.wireColor = yellow
            
            -- 计算创建的对象统计
            local closureCount = 0
            local vShapeCount = 0
            
            -- 统计各类型对象数量
            for obj in createdObjects do
            (
                if findString obj.name "ClosureLine" != undefined then
                    closureCount += 1
                else
                    vShapeCount += 1
            )
            
            messageBox ("成功生成 " + vShapeCount as string + " 个V字形导流线(固定中心模型)和 " + closureCount as string + " 条封闭线段！") title:"完成"
            return mainGroup
        )
        else
        (
            delete mainGroup
            messageBox "未能创建任何模型，请检查参数设置！" title:"警告"
            return undefined
        )
    )
    catch
    (
        print ("generateTrafficGuideLine 错误: " + getCurrentException())
        messageBox "生成导流线时发生错误，请检查控制台输出！" title:"错误"
        return undefined
    )
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
            drawTrafficGuidePreview tgl_selectedSplines tgl_vSpacing tgl_lineThickness tgl_vDirection tgl_standardVAngle tgl_offsetDistance
        )
    )
    catch
    (
        print ("initTrafficGuidePreview 错误: " + getCurrentException())
    )
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
rollout TrafficGuideLineRol "车道导流线生成器 v2.1.0" width:220 height:420
(
    groupBox 'grp1' "样条线选择" pos:[8,8] width:204 height:60 align:#left
    label 'lblInfo' "请选择两条样条线作为车道边界" pos:[15,25] width:190 height:15 align:#left
    button 'btnSelect' "选择样条线" pos:[15,40] width:100 height:25 align:#left
    label 'lblCount' "已选择: 0 条" pos:[125,45] width:80 height:15 align:#left
    
    groupBox 'grp2' "V字形参数" pos:[8,75] width:204 height:145 align:#left
    spinner 'spnStandardAngle' "开合角度:" pos:[15,95] width:150 height:20 range:[15,120,60] type:#float scale:0.1
    spinner 'spnVSpacing' "V字间距:" pos:[15,120] width:150 height:20 range:[100,1000,200] type:#worldunits scale:0.01
    spinner 'spnLineThickness' "线条厚度:" pos:[15,145] width:150 height:20 range:[10,500,100] type:#worldunits scale:0.01
    spinner 'spnOffsetDistance' "偏移距离:" pos:[15,170] width:150 height:20 range:[0,500,30] type:#worldunits scale:0.01
    radiobuttons 'rdoDirection' "V字方向:" pos:[15,195] width:180 height:20 labels:#("正向", "反向") default:1
    
    groupBox 'grp3' "预览和生成" pos:[8,230] width:204 height:80 align:#left
    checkbox 'chkPreview' "显示预览" pos:[15,250] width:80 height:20 align:#left
    button 'btnGenerate' "生成导流线" pos:[50,275] width:120 height:30 align:#left
    
    groupBox 'grp4' "使用说明" pos:[8,320] width:204 height:90 align:#left
    label 'lblHelp1' "1. 选择两条定义车道边界的样条线" pos:[12,335] width:195 height:12 align:#left
    label 'lblHelp2' "2. 调整V字形参数（角度、间距、厚度、偏移）" pos:[12,347] width:195 height:12 align:#left
    label 'lblHelp3' "3. 开启预览查看效果，然后生成" pos:[12,359] width:195 height:12 align:#left
    label 'lblHelp4' "注：使用固定中心模型，边界点约束在边界线上" pos:[12,371] width:195 height:12 align:#left
    label 'lblHelp5' "偏移距离：控制红色线段沿中心线向后的偏移距离" pos:[12,383] width:195 height:12 align:#left
    
    -- 更新预览
    fn updatePreview =
    (
        if chkPreview.checked and tgl_selectedSplines.count >= 2 then
        (
            tgl_standardVAngle = spnStandardAngle.value
            tgl_vSpacing = spnVSpacing.value
            tgl_lineThickness = spnLineThickness.value
            tgl_offsetDistance = spnOffsetDistance.value
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
    
    on spnStandardAngle changed val do updatePreview() 
    on spnVSpacing changed val do updatePreview()
    on spnLineThickness changed val do updatePreview()
    on spnOffsetDistance changed val do updatePreview()
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
            
            -- 收集参数
            local standardAngle = spnStandardAngle.value
            local vSpacing = spnVSpacing.value
            local lineThickness = spnLineThickness.value
            local offsetDistance = spnOffsetDistance.value
            local direction = if rdoDirection.state == 1 then 1 else -1
            
            -- 更新全局标准参数
            tgl_standardVAngle = standardAngle
            tgl_offsetDistance = offsetDistance
            
            -- 生成导流线
            local result = generateTrafficGuideLine tgl_selectedSplines vSpacing lineThickness direction standardAngle
            
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

-- Function definition verification (silent)
try
(
    -- Verify functions are defined without printing
    local functionsOK = (analyzeSplineIntersection != undefined and 
                        calculateBoundaryPoint != undefined)
)
catch
(
    -- Silent error handling
)

CreateDialog TrafficGuideLineRol