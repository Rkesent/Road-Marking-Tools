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
global tgl_centerOffset = 100.0     -- 中点偏移距离 (单位)
global tgl_offsetDistance = 500.0   -- 向后偏移距离 (mm)
global tgl_fixedAngle = 60.0      -- 固定V字形角度 (度)
global tgl_useFixedAngle = true   -- 是否使用固定角度模式
global tgl_lastUpdateTime = 0     -- 上次更新时间 (节流用)
global tgl_previewCache = #()     -- 预览数据缓存
global tgl_cacheValid = false     -- 缓存是否有效
global tgl_lastParams = #()       -- 上次计算的参数

-------
-- 参数比较和缓存管理
-------
fn comparePreviewParams currentParams =
(
    if tgl_lastParams.count != currentParams.count then
        return false
    
    for i = 1 to currentParams.count do
    (
        if tgl_lastParams[i] != currentParams[i] then
            return false
    )
    return true
)

fn updatePreviewCache splines vSpacing direction centerOffset offsetDistance =
(
    local currentParams = #(
        tgl_useFixedAngle,
        tgl_fixedAngle,
        vSpacing,
        direction,
        centerOffset,
        offsetDistance,
        splines[1].name,  -- 样条线标识
        splines[2].name
    )
    
    -- 检查参数是否改变
    if comparePreviewParams currentParams and tgl_cacheValid then
        return tgl_previewCache
    
    -- 参数改变，重新计算缓存
    tgl_lastParams = currentParams
    
    local spline1 = splines[1]
    local spline2 = splines[2]
    
    -- 计算封闭线段数据
    local intersectionInfo = analyzeSplineIntersection spline1 spline2
    local startClosureLine = intersectionInfo[2]
    local closureData = undefined
    
    if startClosureLine != undefined then
    (
        local offsetData = undefined
        if offsetDistance > 0 then
        (
            local spline1Length = curveLength spline1 1
            local spline2Length = curveLength spline2 1
            local offsetParam1 = if spline1Length > 0 then (offsetDistance / spline1Length) else 0.0
            local offsetParam2 = if spline2Length > 0 then (offsetDistance / spline2Length) else 0.0
            offsetParam1 = amax 0.0 (amin 1.0 offsetParam1)
            offsetParam2 = amax 0.0 (amin 1.0 offsetParam2)
            local projectedStart = lengthInterp spline1 1 offsetParam1
            local projectedEnd = lengthInterp spline2 1 offsetParam2
            offsetData = #(projectedStart, projectedEnd)
        )
        closureData = #(startClosureLine, offsetData)
    )
    
    -- 计算V字形数据
    local vPositions = calculateVShapePositions spline1 spline2 vSpacing direction centerOffset
    local vShapeData = #()
    
    for vData in vPositions do
    (
        local vPos = vData[1]
        local vDir = vData[2]
        local leftBoundary = vData[3]
        local rightBoundary = vData[4]
        
        local pathDirection = if vDir != undefined then vDir else [1,0,0]
        pathDirection = pathDirection * direction
        
        local centerBottom = vPos
        local leftTop = leftBoundary
        local rightTop = rightBoundary
        local baseZ = centerBottom.z
        
        local leftTopPreview = [leftTop.x, leftTop.y, baseZ]
        local rightTopPreview = [rightTop.x, rightTop.y, baseZ]
        
        -- 计算centerBottomPreview
        local centerBottomPreview = undefined
        if tgl_useFixedAngle then
        (
            centerBottomPreview = vPos
        )
        else
        (
            centerBottomPreview = if centerOffset > 0 then
                centerBottom + (normalize pathDirection) * centerOffset
            else
                centerBottom
        )
        
        if centerBottomPreview != undefined then
            centerBottomPreview = [centerBottomPreview.x, centerBottomPreview.y, baseZ]
        
        -- 存储预览数据
        append vShapeData #(leftTopPreview, centerBottomPreview, rightTopPreview, centerBottom)
    )
    
    -- 更新缓存
    tgl_previewCache = #(closureData, vShapeData)
    tgl_cacheValid = true
    
    return tgl_previewCache
)

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
--   leftBoundary: 左侧边界点（用于约束检查）
--   rightBoundary: 右侧边界点（用于约束检查）
--   fixedAngle: 固定开合角度（度）
--   armLength: V字形臂长（可选，默认根据边界点距离计算）
--   centerOffset: 中心底部顶点沿中心线向上的偏移距离
-- 返回：V字形网格对象
-------
fn createStandardVShape centerPos pathDirection lineThickness leftBoundary rightBoundary fixedAngle armLength centerOffset =
(
    try
    (
        local vWidth = if lineThickness != undefined then lineThickness else 2.0
        
        -- 计算V字形臂长（如果未指定，使用边界点距离的平均值）
        local defaultArmLength = if armLength != undefined then armLength else 
        (
            local leftDist = distance centerPos leftBoundary
            local rightDist = distance centerPos rightBoundary
            (leftDist + rightDist) / 2.0
        )
        
        -- 使用固定角度计算V字形端点，保持几何重心在centerPos
        local halfAngleRad = degToRad (fixedAngle / 2.0)
        
        -- 计算路径方向的垂直向量（用于确定左右方向）
        local pathDir = normalize pathDirection
        local perpDir = normalize (cross pathDir [0,0,1])
        
        -- 重新计算V字形几何：保持几何重心固定在centerPos
        -- 几何重心 = (leftEnd + rightEnd) / 2 = centerPos
        -- 因此：leftEnd = centerPos + offset, rightEnd = centerPos - offset
        local lateralOffset = perpDir * defaultArmLength * sin halfAngleRad
        local longitudinalOffset = pathDir * defaultArmLength * cos halfAngleRad
        
        -- 计算V字形端点（几何重心固定在centerPos）
        local leftEnd = centerPos + lateralOffset
        local rightEnd = centerPos - lateralOffset
        
        -- 计算V字形顶点（两臂的交汇点）
        -- 在固定角度模式下，centerPos已经是调整后的顶点位置
        local vexPos = if centerOffset != undefined and centerOffset > 0 and not tgl_useFixedAngle then
            centerPos + (normalize pathDirection) * centerOffset
        else
            centerPos  -- 在固定角度模式下，centerPos就是正确的顶点位置
        
        -- 边界约束检查：如果计算的端点超出边界点，则调整端点位置
        local leftBoundaryDist = distance vexPos leftBoundary
        local rightBoundaryDist = distance vexPos rightBoundary
        local leftCalcDist = distance vexPos leftEnd
        local rightCalcDist = distance vexPos rightEnd
        
        if leftCalcDist > leftBoundaryDist then
            leftEnd = leftBoundary
        if rightCalcDist > rightBoundaryDist then
            rightEnd = rightBoundary
        
        -- 确保所有点在同一水平面上
        leftEnd.z = centerPos.z
        rightEnd.z = centerPos.z
        vexPos.z = centerPos.z
        
        -- 计算线条宽度的一半
        local halfWidth = vWidth / 2.0
        
        -- 创建V字形几何体
        local verts = #()
        local faces = #()
        
        -- 计算V字形的顶点（考虑线条宽度）
        -- 左臂方向和垂直方向
        local leftArmDir = normalize (leftEnd - vexPos)
        local leftPerpDir = normalize (cross leftArmDir [0,0,1])
        
        -- 右臂方向和垂直方向
        local rightArmDir = normalize (rightEnd - vexPos)
        local rightPerpDir = normalize (cross rightArmDir [0,0,1])
        
        -- 左臂的四个顶点
        append verts (vexPos + leftPerpDir * halfWidth)     -- 1: 左臂内侧底部
        append verts (vexPos - leftPerpDir * halfWidth)     -- 2: 左臂外侧底部
        append verts (leftEnd + leftPerpDir * halfWidth)       -- 3: 左臂内侧顶部
        append verts (leftEnd - leftPerpDir * halfWidth)       -- 4: 左臂外侧顶部
        
        -- 右臂的四个顶点
        append verts (vexPos - rightPerpDir * halfWidth)    -- 5: 右臂内侧底部
        append verts (vexPos + rightPerpDir * halfWidth)    -- 6: 右臂外侧底部
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
        
        -- 设置网格位置（相对于世界坐标原点）
        vMesh.pos = [0,0,0]
        
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
-- 根据中点偏移量计算V字形开合角度
-- 参数：
--   centerPos: V字形中心位置
--   centerDir: 中心线方向
--   leftBoundary: 左边界点
--   rightBoundary: 右边界点
--   offsetDistance: 从中心点沿中心线向上的偏移距离
-- 返回：计算出的开合角度（度）
-------
fn calculateAngleFromOffset centerPos centerDir leftBoundary rightBoundary offsetDistance =
(
    -- 计算沿中心线向上偏移后的目标点（centerBottomPreview向上偏移）
    local targetPoint = centerPos + (normalize centerDir) * offsetDistance
    
    -- 计算从目标点到左右边界的向量
    local toLeft = normalize (leftBoundary - targetPoint)
    local toRight = normalize (rightBoundary - targetPoint)
    
    -- 计算两个向量之间的夹角
    local dotProduct = dot toLeft toRight
    dotProduct = amax -1.0 (amin 1.0 dotProduct)  -- 限制在有效范围内
    local angleRad = acos dotProduct
    local angleDeg = radToDeg angleRad
    
    return angleDeg
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
-- 反向计算中心线偏移距离（根据目标角度）
-- 参数：
--   centerPos: V字形中心位置
--   centerDir: 中心线方向
--   leftBoundary: 左边界点
--   rightBoundary: 右边界点
--   targetAngle: 目标开合角度（度）
--   maxOffset: 最大搜索偏移距离（可选，默认1000）
-- 返回：实现目标角度所需的中心偏移距离
-------
fn calculateOffsetFromAngle centerPos centerDir leftBoundary rightBoundary targetAngle maxOffset:1000.0 =
(
    try
    (
        -- 二分搜索法寻找最佳偏移距离
        local minOffset = 0.0
        local maxSearch = if maxOffset != undefined then maxOffset else 1000.0
        local tolerance = 0.1  -- 角度误差容差（度）
        local maxIterations = 20
        
        -- 首先检查目标角度是否在可达范围内
        local minAngle = calculateAngleFromOffset centerPos centerDir leftBoundary rightBoundary 0.0
        local maxAngle = calculateAngleFromOffset centerPos centerDir leftBoundary rightBoundary maxSearch
        
        -- 如果目标角度超出范围，返回边界值
        if targetAngle >= minAngle then
            return 0.0
        if targetAngle <= maxAngle then
            return maxSearch
        
        -- 二分搜索
        for iteration = 1 to maxIterations do
        (
            local midOffset = (minOffset + maxSearch) / 2.0
            local currentAngle = calculateAngleFromOffset centerPos centerDir leftBoundary rightBoundary midOffset
            local angleDiff = abs (currentAngle - targetAngle)
            
            -- 如果误差在容差范围内，返回结果
            if angleDiff < tolerance then
                return midOffset
            
            -- 根据角度差异调整搜索范围
            if currentAngle > targetAngle then
                minOffset = midOffset
            else
                maxSearch = midOffset
        )
        
        -- 返回最接近的结果
        return (minOffset + maxSearch) / 2.0
    )
    catch
    (
        print ("calculateOffsetFromAngle 错误: " + getCurrentException())
        return 0.0
    )
)

-------
-- 角度与偏移距离的数学关系分析函数
-- 参数：
--   centerPos: V字形中心位置
--   centerDir: 中心线方向
--   leftBoundary: 左边界点
--   rightBoundary: 右边界点
--   offsetRange: 偏移距离范围数组，如#(0, 50, 100, 150, 200)
-- 返回：角度和偏移距离的对应关系数组
-------
fn analyzeAngleOffsetRelation centerPos centerDir leftBoundary rightBoundary offsetRange:#(0, 25, 50, 75, 100, 125, 150, 175, 200) =
(
    local results = #()
    
    for offset in offsetRange do
    (
        local angle = calculateAngleFromOffset centerPos centerDir leftBoundary rightBoundary offset
        append results #(offset, angle)
        print ("偏移距离: " + offset as string + "mm → 角度: " + (formattedPrint angle format:":.1f") + "°")
    )
    
    return results
)

-------
-- 便捷的反向计算函数：根据标准V形角度计算所需偏移
-- 参数：
--   centerPos: V字形中心位置  
--   centerDir: 中心线方向
--   leftBoundary: 左边界点
--   rightBoundary: 右边界点
--   desiredAngle: 期望的V形角度（度）
-- 返回：实现该角度所需的中心偏移距离
-------
fn getOffsetForAngle centerPos centerDir leftBoundary rightBoundary desiredAngle =
(
    local result = calculateOffsetFromAngle centerPos centerDir leftBoundary rightBoundary desiredAngle
    print ("目标角度: " + desiredAngle as string + "° → 需要偏移距离: " + result as string + "mm")
    return result
)

-------
-- 根据固定角度和中点偏移量计算V字形顶点位置
-- 参数：
--   centerPos: V字形中心位置
--   centerDir: 中心线方向
--   leftBoundary: 左边界点
--   rightBoundary: 右边界点
--   fixedAngle: 固定的V字形角度（度）
--   centerOffset: 中心底部顶点的偏移量
-- 返回：调整后的V字形顶点位置
-------
fn calculateFixedAngleVertexPosition centerPos centerDir leftBoundary rightBoundary fixedAngle centerOffset =
(
    try
    (
        -- 计算基础的中心顶点位置（沿中心线向上偏移）
        -- 在固定角度模式下，centerOffset 直接控制顶点偏移
        local baseVertexPos = centerPos + (normalize centerDir) * centerOffset
        
        -- 使用固定角度计算理论上的V字形端点
        local halfAngleRad = degToRad (fixedAngle / 2.0)
        local pathDir = normalize centerDir
        local perpDir = normalize (cross pathDir [0,0,1])
        
        -- 计算固定角度下的理论端点方向
        local leftArmDir = [pathDir.x * cos (-halfAngleRad) - pathDir.y * sin (-halfAngleRad),
                           pathDir.x * sin (-halfAngleRad) + pathDir.y * cos (-halfAngleRad),
                           0]
        local rightArmDir = [pathDir.x * cos halfAngleRad - pathDir.y * sin halfAngleRad,
                            pathDir.x * sin halfAngleRad + pathDir.y * cos halfAngleRad,
                            0]
        
        -- 计算到边界点的距离
        local leftDist = distance baseVertexPos leftBoundary
        local rightDist = distance baseVertexPos rightBoundary
        local avgDist = (leftDist + rightDist) / 2.0
        
        -- 计算理论端点位置
        local theoreticalLeftEnd = baseVertexPos + leftArmDir * avgDist
        local theoreticalRightEnd = baseVertexPos + rightArmDir * avgDist
        
        -- 检查理论端点是否在边界约束内，如果超出则调整顶点位置
        local leftBoundaryDist = distance baseVertexPos leftBoundary
        local rightBoundaryDist = distance baseVertexPos rightBoundary
        local theoreticalLeftDist = distance baseVertexPos theoreticalLeftEnd
        local theoreticalRightDist = distance baseVertexPos theoreticalRightEnd
        
        -- 如果理论端点超出边界，需要调整顶点位置
        local adjustmentNeeded = false
        local adjustmentScale = 1.0
        
        if theoreticalLeftDist > leftBoundaryDist then
        (
            adjustmentScale = amin adjustmentScale (leftBoundaryDist / theoreticalLeftDist)
            adjustmentNeeded = true
        )
        if theoreticalRightDist > rightBoundaryDist then
        (
            adjustmentScale = amin adjustmentScale (rightBoundaryDist / theoreticalRightDist)
            adjustmentNeeded = true
        )
        
        -- 如果需要调整，重新计算顶点位置
        if adjustmentNeeded then
        (
            -- 向中心位置方向调整顶点
            local adjustedVertexPos = centerPos + (baseVertexPos - centerPos) * adjustmentScale
            return adjustedVertexPos
        )
        else
        (
            return baseVertexPos
        )
    )
    catch
    (
        return centerPos
    )
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
--   centerOffset: 中心底部顶点沿中心线向上的偏移距离
-- 返回：V字形网格对象
-------
fn createVShapeModel vPos vDir leftBoundary rightBoundary leftSpline rightSpline lineThickness direction fixedAngle centerOffset = 
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
        
        local standardVShape = createStandardVShape vPos pathDirection lineThickness leftBoundary rightBoundary fixedAngle undefined centerOffset
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
fn calculateVShapePositions spline1 spline2 vSpacing direction centerOffset =
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
                                
                                -- 根据模式计算V字形角度和顶点位置
                                local calculatedAngle = 0.0
                                local adjustedVPos = vPos
                                
                                if tgl_useFixedAngle then
                                (
                                    -- 固定角度模式：使用全局固定角度，根据偏移量调整顶点位置
                                    calculatedAngle = tgl_fixedAngle
                                    adjustedVPos = calculateFixedAngleVertexPosition vPos vDir leftBoundary rightBoundary tgl_fixedAngle centerOffset
                                )
                                else
                                (
                                    -- 动态角度模式：根据中点偏移量计算角度
                                    calculatedAngle = calculateAngleFromOffset vPos vDir leftBoundary rightBoundary centerOffset
                                    adjustedVPos = vPos
                                )
                                
                                append result #(adjustedVPos, vDir, leftBoundary, rightBoundary, calculatedAngle)
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
-- 优化的预览绘制函数（使用缓存数据）
-------
fn drawTrafficGuidePreview splines vSpacing lineThick direction centerOffset offsetDistance =
(
    if splines.count >= 2 then
    (
        -- 获取缓存的预览数据
        local previewData = updatePreviewCache splines vSpacing direction centerOffset offsetDistance
        local closureData = previewData[1]
        local vShapeData = previewData[2]
        
        gw.setTransform(matrix3 1)
        
        -- 绘制封闭线段
        if closureData != undefined then
        (
            local startClosureLine = closureData[1]
            local offsetData = closureData[2]
            
            -- 绘制原始封闭线段
            gw.setColor #line (color 0 255 255)  -- 青色封闭线
            gw.polyline #(startClosureLine[1], startClosureLine[2]) false
            
            -- 绘制中心偏移线段
            if offsetData != undefined then
            (
                gw.setColor #line (color 255 0 0)  -- 红色中心偏移线段
                gw.polyline #(offsetData[1], offsetData[2]) false
            )
        )
        
        -- 绘制V字形
        gw.setColor #line tgl_previewColor
        for vShape in vShapeData do
        (
            local leftTopPreview = vShape[1]
            local centerBottomPreview = vShape[2]
            local rightTopPreview = vShape[3]
            local centerBottom = vShape[4]
            
            -- 绘制V字形中心骨架线
            gw.polyline #(leftTopPreview, centerBottomPreview, rightTopPreview) false
            
            -- 绘制中心标记点
            gw.setColor #line (color 255 0 0)  -- 红色标记点
            local markerSize = 10.0
            gw.polyline #([centerBottom.x - markerSize, centerBottom.y, centerBottom.z], [centerBottom.x + markerSize, centerBottom.y, centerBottom.z]) false
            gw.polyline #([centerBottom.x, centerBottom.y - markerSize, centerBottom.z], [centerBottom.x, centerBottom.y + markerSize, centerBottom.z]) false
            gw.setColor #line tgl_previewColor
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
fn generateTrafficGuideLine splines vSpacing lineThick direction centerOffset =
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
        local vPositions = calculateVShapePositions spline1 spline2 vSpacing direction centerOffset
    
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
            local vShapeMesh = createVShapeModel vPos vDir leftBoundary rightBoundary spline1 spline2 lineThick direction vAngle centerOffset
            
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
-- 优化的预览系统
-------
fn initTrafficGuidePreview =
(
    try
    (
        if tgl_previewEnabled and tgl_selectedSplines.count >= 2 then
        (
            -- 智能节流机制：只有缓存失效时才重新绘制
            if not tgl_cacheValid then
            (
                drawTrafficGuidePreview tgl_selectedSplines tgl_vSpacing tgl_lineThickness tgl_vDirection tgl_centerOffset tgl_offsetDistance
            )
            else
            (
                -- 使用缓存数据快速重绘
                local previewData = tgl_previewCache
                if previewData.count > 0 then
                (
                    local closureData = previewData[1]
                    local vShapeData = previewData[2]
                    
                    gw.setTransform(matrix3 1)
                    
                    -- 快速绘制封闭线段
                    if closureData != undefined then
                    (
                        local startClosureLine = closureData[1]
                        local offsetData = closureData[2]
                        
                        gw.setColor #line (color 0 255 255)
                        gw.polyline #(startClosureLine[1], startClosureLine[2]) false
                        
                        if offsetData != undefined then
                        (
                            gw.setColor #line (color 255 0 0)
                            gw.polyline #(offsetData[1], offsetData[2]) false
                        )
                    )
                    
                    -- 快速绘制V字形
                    gw.setColor #line tgl_previewColor
                    for vShape in vShapeData do
                    (
                        gw.polyline #(vShape[1], vShape[2], vShape[3]) false
                        
                        local centerBottom = vShape[4]
                        local markerSize = 10.0
                        gw.setColor #line (color 255 0 0)
                        gw.polyline #([centerBottom.x - markerSize, centerBottom.y, centerBottom.z], [centerBottom.x + markerSize, centerBottom.y, centerBottom.z]) false
                        gw.polyline #([centerBottom.x, centerBottom.y - markerSize, centerBottom.z], [centerBottom.x, centerBottom.y + markerSize, centerBottom.z]) false
                        gw.setColor #line tgl_previewColor
                    )
                    
                    gw.enlargeUpdateRect #whole
                    gw.updateScreen()
                )
            )
        )
    )
    catch
    (
        -- 静默处理错误
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
rollout TrafficGuideLineRol "车道导流线生成器 v2.2.0" width:220 height:505
(
    groupBox 'grp1' "样条线选择" pos:[8,8] width:204 height:60 align:#left
    label 'lblInfo' "请选择两条样条线作为车道边界" pos:[15,25] width:190 height:15 align:#left
    button 'btnSelect' "选择样条线" pos:[15,40] width:100 height:25 align:#left
    label 'lblCount' "已选择: 0 条" pos:[125,45] width:80 height:15 align:#left
    
    groupBox 'grp2' "V字形参数" pos:[8,75] width:204 height:195 align:#left
    checkbox 'chkFixedAngle' "固定角度模式" pos:[15,95] width:100 height:20 align:#left checked:true
    spinner 'spnFixedAngle' "固定角度:" pos:[15,115] width:150 height:20 range:[15,180,60] type:#float enabled:true
    spinner 'spnCenterOffset' "中点偏移:" pos:[15,140] width:150 height:20 range:[0,500,100] type:#worldunits scale:0.01
    button 'btnAngleCalc' "角度计算器" pos:[170,140] width:35 height:20 align:#left enabled:false
    spinner 'spnVSpacing' "V字间距:" pos:[15,165] width:150 height:20 range:[100,1000,200] type:#worldunits scale:0.01
    spinner 'spnLineThickness' "线条厚度:" pos:[15,190] width:150 height:20 range:[10,500,100] type:#worldunits scale:0.01
    spinner 'spnOffsetDistance' "偏移距离:" pos:[15,215] width:150 height:20 range:[0,500,30] type:#worldunits scale:0.01
    radiobuttons 'rdoDirection' "V字方向:" pos:[15,240] width:180 height:20 labels:#("正向", "反向") default:1
    
    groupBox 'grp3' "预览和生成" pos:[8,280] width:204 height:80 align:#left
    checkbox 'chkPreview' "显示预览" pos:[15,300] width:80 height:20 align:#left
    button 'btnGenerate' "生成导流线" pos:[50,325] width:120 height:30 align:#left
    
    groupBox 'grp4' "使用说明" pos:[8,370] width:204 height:125 align:#left
    label 'lblHelp1' "1. 选择两条定义车道边界的样条线" pos:[12,385] width:195 height:12 align:#left
    label 'lblHelp2' "2. 选择固定角度模式或动态角度模式" pos:[12,397] width:195 height:12 align:#left
    label 'lblHelp3' "3. 调整V字形参数（角度、偏移、间距等）" pos:[12,409] width:195 height:12 align:#left
    label 'lblHelp4' "4. 使用角度计算器进行精确设置" pos:[12,421] width:195 height:12 align:#left
    label 'lblHelp5' "5. 开启预览查看效果，然后生成" pos:[12,433] width:195 height:12 align:#left
    label 'lblHelp6' "注：固定角度模式保证所有V形角度一致" pos:[12,445] width:195 height:12 align:#left
    label 'lblHelp7' "中点偏移：控制V形中心顶点的位置调整" pos:[12,457] width:195 height:12 align:#left
    
    -- 更新预览
    fn updatePreview =
    (
        if chkPreview.checked and tgl_selectedSplines.count >= 2 then
        (
            -- 更新全局参数
            tgl_useFixedAngle = chkFixedAngle.checked
            tgl_fixedAngle = spnFixedAngle.value
            tgl_centerOffset = spnCenterOffset.value
            tgl_vSpacing = spnVSpacing.value
            tgl_lineThickness = spnLineThickness.value
            tgl_offsetDistance = spnOffsetDistance.value
            tgl_vDirection = if rdoDirection.state == 1 then 1 else -1
            
            -- 标记缓存失效，强制重新计算
            tgl_cacheValid = false
            redrawviews()
        )
    )
    
    -- 清除预览缓存
    fn clearPreviewCache =
    (
        tgl_previewCache = #()
        tgl_cacheValid = false
        tgl_lastParams = #()
    )
    
    -- 界面事件
    on TrafficGuideLineRol open do
    (
        unregisterPreview()
        clearPreviewCache()  -- 清除缓存
        tgl_previewEnabled = false
        chkPreview.checked = false
        tgl_selectedSplines = #()
        lblCount.text = "已选择: 0 条"
        
        -- 初始化固定角度模式UI状态
        chkFixedAngle.checked = tgl_useFixedAngle
        spnFixedAngle.value = tgl_fixedAngle
        spnFixedAngle.enabled = tgl_useFixedAngle
        btnAngleCalc.enabled = not tgl_useFixedAngle
    )
    
    on TrafficGuideLineRol close do
    (
        unregisterPreview()
        clearPreviewCache()  -- 清除缓存
        tgl_selectedSplines = #()
        tgl_previewEnabled = false
    )
    
    on btnSelect pressed do
    (
        clearPreviewCache()  -- 清除缓存，因为样条线可能改变
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
    
    on chkFixedAngle changed state do
    (
        tgl_useFixedAngle = state
        spnFixedAngle.enabled = state
        btnAngleCalc.enabled = not state
        updatePreview()
    )
    
    on spnFixedAngle changed val do updatePreview()
    on spnCenterOffset changed val do updatePreview() 
    on spnVSpacing changed val do updatePreview()
    on spnLineThickness changed val do updatePreview()
    on spnOffsetDistance changed val do updatePreview()
    on rdoDirection changed state do updatePreview()
    
    on btnAngleCalc pressed do
    (
        if tgl_selectedSplines.count >= 2 then
        (
            -- 创建角度计算器对话框
            rollout AngleCalculatorRol "V形角度计算器" width:250 height:320
            (
                groupBox 'grp1' "角度分析" pos:[8,8] width:234 height:120 align:#left
                button 'btnAnalyze' "分析角度-偏移关系" pos:[15,25] width:140 height:25 align:#left
                label 'lblCurrentAngle' "当前角度: --°" pos:[15,55] width:220 height:15 align:#left
                label 'lblCurrentOffset' "当前偏移: --mm" pos:[15,70] width:220 height:15 align:#left
                
                groupBox 'grp2' "反向计算" pos:[8,135] width:234 height:80 align:#left
                spinner 'spnTargetAngle' "目标角度(°):" pos:[15,155] width:150 height:20 range:[10,180,60] type:#float
                button 'btnCalcOffset' "计算所需偏移" pos:[15,185] width:100 height:25 align:#left
                label 'lblResult' "结果: --mm" pos:[125,190] width:100 height:15 align:#left
                
                groupBox 'grp3' "快速设置" pos:[8,225] width:234 height:80 align:#left
                button 'btnSet30' "30°" pos:[15,245] width:40 height:25 align:#left
                button 'btnSet45' "45°" pos:[60,245] width:40 height:25 align:#left
                button 'btnSet60' "60°" pos:[105,245] width:40 height:25 align:#left
                button 'btnSet90' "90°" pos:[150,245] width:40 height:25 align:#left
                button 'btnSet120' "120°" pos:[195,245] width:40 height:25 align:#left
                button 'btnApplyOffset' "应用到主界面" pos:[70,275] width:110 height:25 align:#left
                
                local calculatedOffset = 0.0
                
                fn getCurrentVShapeData =
                (
                    -- 获取当前第一个V形的数据用于计算
                    local vPositions = calculateVShapePositions tgl_selectedSplines[1] tgl_selectedSplines[2] tgl_vSpacing tgl_vDirection tgl_centerOffset
                    if vPositions.count > 0 then
                        return vPositions[1]
                    else
                        return undefined
                )
                
                on btnAnalyze pressed do
                (
                    local vData = getCurrentVShapeData()
                    if vData != undefined then
                    (
                        local centerPos = vData[1]
                        local centerDir = vData[2]
                        local leftBoundary = vData[3]
                        local rightBoundary = vData[4]
                        
                        print "=== 角度-偏移关系分析 ==="
                        analyzeAngleOffsetRelation centerPos centerDir leftBoundary rightBoundary
                        
                        -- 显示当前参数的角度
                        local currentAngle = calculateAngleFromOffset centerPos centerDir leftBoundary rightBoundary tgl_centerOffset
                        lblCurrentAngle.text = "当前角度: " + (formattedPrint currentAngle format:":.1f") + "°"
                        lblCurrentOffset.text = "当前偏移: " + tgl_centerOffset as string + "mm"
                    )
                    else
                    (
                        messageBox "无法获取V形数据，请检查样条线选择！" title:"错误"
                    )
                )
                
                on btnCalcOffset pressed do
                (
                    local vData = getCurrentVShapeData()
                    if vData != undefined then
                    (
                        local centerPos = vData[1]
                        local centerDir = vData[2]
                        local leftBoundary = vData[3]
                        local rightBoundary = vData[4]
                        
                        calculatedOffset = getOffsetForAngle centerPos centerDir leftBoundary rightBoundary spnTargetAngle.value
                        lblResult.text = "结果: " + (formattedPrint calculatedOffset format:":.1f") + "mm"
                    )
                    else
                    (
                        messageBox "无法获取V形数据，请检查样条线选择！" title:"错误"
                    )
                )
                
                fn setAngleAndCalculate angle =
                (
                    spnTargetAngle.value = angle
                    btnCalcOffset.pressed()
                )
                
                on btnSet30 pressed do setAngleAndCalculate 30
                on btnSet45 pressed do setAngleAndCalculate 45  
                on btnSet60 pressed do setAngleAndCalculate 60
                on btnSet90 pressed do setAngleAndCalculate 90
                on btnSet120 pressed do setAngleAndCalculate 120
                
                on btnApplyOffset pressed do
                (
                    if calculatedOffset > 0 then
                    (
                        TrafficGuideLineRol.spnCenterOffset.value = calculatedOffset
                        TrafficGuideLineRol.updatePreview()
                        messageBox ("已设置中点偏移为: " + calculatedOffset as string + "mm") title:"完成"
                        destroyDialog AngleCalculatorRol
                    )
                    else
                    (
                        messageBox "请先计算偏移距离！" title:"提示"
                    )
                )
            )
            
            createDialog AngleCalculatorRol modal:true
        )
        else
        (
            messageBox "请先选择两条样条线！" title:"提示"
        )
    )
    
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
            local useFixedAngle = chkFixedAngle.checked
            local fixedAngle = spnFixedAngle.value
            local centerOffset = spnCenterOffset.value
            local vSpacing = spnVSpacing.value
            local lineThickness = spnLineThickness.value
            local offsetDistance = spnOffsetDistance.value
            local direction = if rdoDirection.state == 1 then 1 else -1
            
            -- 更新全局参数
            tgl_useFixedAngle = useFixedAngle
            tgl_fixedAngle = fixedAngle
            tgl_centerOffset = centerOffset
            tgl_offsetDistance = offsetDistance
            
            -- 生成导流线
            local result = generateTrafficGuideLine tgl_selectedSplines vSpacing lineThickness direction centerOffset
            
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