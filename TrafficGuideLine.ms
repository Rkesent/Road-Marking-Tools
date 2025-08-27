-------
-- TrafficGuideLine v1.0.0 - 车道导流线生成器
-- 功能：基于两条样条线生成V字形导流线标记
-------

-- 清除之前的函数定义以避免冲突
try (analyzeSplineIntersection = undefined) catch()
try (calculateBoundaryPoint = undefined) catch()
try (tgl_calculateSingleVShapePoints = undefined) catch()
try (tgl_calculateDualVShapePoints = undefined) catch()
try (calculateDualVShapePoints = undefined) catch()
try (drawTrafficGuidePreviewOptimal = undefined) catch()

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
global tgl_lastUpdateTime = 0     -- 上次更新时间 (节流用)

-- 新增双V字形相关参数（采用VShapeGenerator的命名规范）
global tgl_armLength = 300.0      -- V字形臂长 (mm) - 对应vsg_armLength
global tgl_acDistance = 200.0     -- A、C两点间距离 (mm) - 对应vsg_acDistance
global tgl_vShapeDistance = 200.0 -- 两个V字形之间的距离 (mm) - 对应vsg_vShapeDistance

-- 移除了复杂的缓存系统，预览数据现在实时计算

-------
-- 从VShapeGenerator.ms集成的双V字形计算函数
-------

-------
-- 计算单个V字形的三个关键点（A、B、C）
-- 参数：
--   centerPos: B点位置（顶点中心）
--   direction: 前进方向向量
--   armLength: 臂长（A、C到B的距离）
--   acDistance: A、C两点间的距离
-- 返回：#(pointA, pointB, pointC)
-------
fn tgl_calculateSingleVShapePoints centerPos direction armLength acDistance =
(
    try
    (
        -- 标准化方向向量
        local forwardDir = normalize direction
        
        -- B点就是中心点
        local pointB = centerPos
        
        -- 根据A、C距离和臂长计算角度
        -- 使用余弦定理：acDistance² = armLength² + armLength² - 2*armLength*armLength*cos(angle)
        -- 简化为：acDistance² = 2*armLength²*(1 - cos(angle))
        -- 所以：cos(angle) = 1 - acDistance²/(2*armLength²)
        local cosAngle = 1.0 - (acDistance * acDistance) / (2.0 * armLength * armLength)
        
        -- 限制cosAngle在有效范围内
        if cosAngle > 1.0 then cosAngle = 1.0
        if cosAngle < -1.0 then cosAngle = -1.0
        
        -- 计算角度（弧度）
        local angleRad = acos(cosAngle)
        local halfAngleRad = angleRad / 2.0
        
        -- 计算左臂方向（逆时针旋转）
        local leftArmDir = [forwardDir.x * cos(-halfAngleRad) - forwardDir.y * sin(-halfAngleRad),
                           forwardDir.x * sin(-halfAngleRad) + forwardDir.y * cos(-halfAngleRad),
                           0]
        
        -- 计算右臂方向（顺时针旋转）
        local rightArmDir = [forwardDir.x * cos(halfAngleRad) - forwardDir.y * sin(halfAngleRad),
                            forwardDir.x * sin(halfAngleRad) + forwardDir.y * cos(halfAngleRad),
                            0]
        
        -- 计算A点和C点位置
        local pointA = pointB + leftArmDir * armLength
        local pointC = pointB + rightArmDir * armLength
        
        return #(pointA, pointB, pointC)
    )
    catch
    (
        -- 如果计算失败，返回默认位置
        return #(centerPos, centerPos, centerPos)
    )
)

-------
-- 计算双V字形的六个关键点（两个V字形）
-- 参数：
--   centerPos: 中心位置
--   direction: 前进方向向量
--   armLength: 臂长（A、C到B的距离）
--   acDistance: A、C两点间的距离
--   vShapeDistance: 两个V字形之间的距离
-- 返回：#(#(pointA1, pointB1, pointC1), #(pointA2, pointB2, pointC2))
-------
fn tgl_calculateDualVShapePoints centerPos direction armLength acDistance vShapeDistance =
(
    try
    (
        -- 标准化方向向量
        local forwardDir = normalize direction
        
        -- 计算垂直方向（沿Y轴前后分布）
        local offsetDir = [0,1,0]
        
        -- 计算两个V字形的中心位置（沿Y轴前后偏移）
        local halfDistance = vShapeDistance / 2.0
        local centerPos1 = centerPos - offsetDir * halfDistance  -- 后方V字形
        local centerPos2 = centerPos + offsetDir * halfDistance  -- 前方V字形
        
        -- 计算第一个V字形的点
        local vShape1 = tgl_calculateSingleVShapePoints centerPos1 direction armLength acDistance
        
        -- 计算第二个V字形的点
        local vShape2 = tgl_calculateSingleVShapePoints centerPos2 direction armLength acDistance
        
        return #(vShape1, vShape2)
    )
    catch
    (
        -- 如果计算失败，返回默认位置
        local defaultPoints = #(centerPos, centerPos, centerPos)
        return #(defaultPoints, defaultPoints)
    )
)

-------
-- 计算双V字形的六个关键点（两个V字形）- 新算法替换中心骨骼生成
-- 参数：
--   centerPos: 中心位置
--   direction: 前进方向向量
--   armLength: 臂长（A、C到B的距离）
--   acDistance: A、C两点间的距离
--   vShapeDistance: 两个V字形之间的距离
-- 返回：#(#(pointA1, pointB1, pointC1), #(pointA2, pointB2, pointC2))
-------
fn calculateDualVShapePoints centerPos direction armLength acDistance vShapeDistance =
(
    -- 直接调用新的双V字形算法
    return tgl_calculateDualVShapePoints centerPos direction armLength acDistance vShapeDistance
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
-- 创建标准V字形模板（新架构：模板+实例化）
-- 参数：
--   armLength: V字形臂长
--   angle: V字形开合角度（度）
--   thickness: 线条厚度
--   templateName: 模板名称
-- 返回：标准V字形模板对象
-------
fn createVShapeTemplate armLength:300.0 angle:60.0 thickness:100.0 templateName:"VShapeTemplate" =
(
    try
    (
        -- 计算V字形几何参数
        local halfAngleRad = degToRad (angle / 2.0)
        local halfWidth = thickness / 2.0
        
        -- 创建标准V字形，顶点在原点，朝向+Y方向
        local verts = #()
        local faces = #()
        
        -- V字形顶点位置（原点）
        local apex = [0, 0, 0]
        
        -- 计算左右臂端点（相对于原点）
        local leftEnd = [armLength * sin(-halfAngleRad), armLength * cos(-halfAngleRad), 0]
        local rightEnd = [armLength * sin(halfAngleRad), armLength * cos(halfAngleRad), 0]
        
        -- 计算各臂的垂直方向
        local leftArmDir = normalize (leftEnd - apex)
        local leftPerpDir = normalize (cross leftArmDir [0,0,1])
        local rightArmDir = normalize (rightEnd - apex)
        local rightPerpDir = normalize (cross rightArmDir [0,0,1])
        
        -- 左臂的四个顶点
        append verts (apex + leftPerpDir * halfWidth)        -- 1: 左臂内侧底部
        append verts (apex - leftPerpDir * halfWidth)        -- 2: 左臂外侧底部
        append verts (leftEnd + leftPerpDir * halfWidth)     -- 3: 左臂内侧顶部
        append verts (leftEnd - leftPerpDir * halfWidth)     -- 4: 左臂外侧顶部
        
        -- 右臂的四个顶点
        append verts (apex - rightPerpDir * halfWidth)      -- 5: 右臂内侧底部
        append verts (apex + rightPerpDir * halfWidth)      -- 6: 右臂外侧底部
        append verts (rightEnd - rightPerpDir * halfWidth)  -- 7: 右臂内侧顶部
        append verts (rightEnd + rightPerpDir * halfWidth)  -- 8: 右臂外侧顶部
        
        -- 创建面（三角形）
        -- 左臂的面
        append faces [1, 2, 3]  -- 左臂三角形1
        append faces [2, 4, 3]  -- 左臂三角形2
        
        -- 右臂的面
        append faces [5, 6, 7]  -- 右臂三角形1
        append faces [6, 8, 7]  -- 右臂三角形2
        
        -- 创建mesh对象
        local templateMesh = mesh vertices:verts faces:faces
        templateMesh.name = templateName
        
        -- 设置材质ID
        for i = 1 to templateMesh.numfaces do
        (
            setFaceMatID templateMesh i 1
        )
        
        -- 设置模板位置在原点
        templateMesh.pos = [0,0,0]
        templateMesh.wireColor = yellow
        
        update templateMesh
        return templateMesh
    )
    catch
    (
        print ("createVShapeTemplate 错误: " + getCurrentException())
        return undefined
    )
)

-------
-- 将V字形模板实例化到指定位置和方向
-- 参数：
--   template: V字形模板对象
--   position: 目标位置
--   direction: 目标方向向量
--   instanceName: 实例名称
-- 返回：实例化的V字形对象
-------
fn instanceVShapeAtPosition template position direction instanceName:"VShapeInstance" =
(
    try
    (
        if template == undefined then
            return undefined
            
        -- 复制模板
        local instance = copy template
        instance.name = instanceName + "_" + (random 1000 9999) as string
        
        -- 计算变换矩阵
        -- 标准方向是+Y，需要旋转到目标方向
        local standardDir = [0, 1, 0]  -- 模板的标准朝向
        local targetDir = normalize direction
        
        -- 计算旋转角度
        local dotProduct = dot standardDir targetDir
        dotProduct = amax -1.0 (amin 1.0 dotProduct)  -- 限制范围
        local rotAngle = acos dotProduct
        
        -- 计算旋转轴（Z轴旋转）
        local rotAxis = [0, 0, 1]
        
        -- 处理特殊情况：方向完全相反
        if dotProduct < -0.999 then
            rotAngle = pi
        else if dotProduct > 0.999 then
            rotAngle = 0
        else
        (
            -- 确定旋转方向
            local crossProduct = cross standardDir targetDir
            if crossProduct.z < 0 then
                rotAngle = -rotAngle
        )
        
        -- 创建变换矩阵
        local rotMatrix = rotateZMatrix rotAngle
        local transMatrix = transMatrix position
        local finalMatrix = rotMatrix * transMatrix
        
        -- 应用变换
        instance.transform = finalMatrix
        
        return instance
    )
    catch
    (
        print ("instanceVShapeAtPosition 错误: " + getCurrentException())
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

-- 移除了复杂的角度计算功能，简化为固定角度模式


-------
-- 基于双V字形数据创建3D模型（新算法）
-- 参数：
--   dualVShapes: 双V字形数据 #(#(pointA1, pointB1, pointC1), #(pointA2, pointB2, pointC2))
--   lineThickness: 线条厚度
--   modelName: 模型名称前缀
-- 返回：双V字形网格对象数组
-------
fn createDualVShapeModel dualVShapes lineThickness modelName:"DualVShape" =
(
    try
    (
        if dualVShapes == undefined or dualVShapes.count != 2 then
        (
            print "createDualVShapeModel: 双V字形数据无效"
            return #()
        )
        
        local resultMeshes = #()
        
        -- 处理两个V字形
        for vIdx = 1 to 2 do
        (
            local vShapePoints = dualVShapes[vIdx]
            if vShapePoints.count == 3 then
            (
                local pointA = vShapePoints[1]
                local pointB = vShapePoints[2]
                local pointC = vShapePoints[3]
                
                -- 创建单个V字形的网格
                local vShapeMesh = createSingleVShapeMesh pointA pointB pointC lineThickness (modelName + "_" + vIdx as string)
                if vShapeMesh != undefined then
                    append resultMeshes vShapeMesh
            )
        )
        
        return resultMeshes
    )
    catch
    (
        print ("createDualVShapeModel 错误: " + getCurrentException())
        return #()
    )
)

-------
-- 创建单个V字形网格（基于三个点）
-- 参数：
--   pointA: A点位置
--   pointB: B点位置（顶点）
--   pointC: C点位置
--   thickness: 线条厚度
--   meshName: 网格名称
-- 返回：V字形网格对象
-------
fn createSingleVShapeMesh pointA pointB pointC thickness meshName =
(
    try
    (
        local halfWidth = thickness / 2.0
        local verts = #()
        local faces = #()
        
        -- 计算左臂方向和垂直方向
        local leftArmDir = normalize (pointA - pointB)
        local leftPerpDir = normalize (cross leftArmDir [0,0,1])
        
        -- 计算右臂方向和垂直方向
        local rightArmDir = normalize (pointC - pointB)
        local rightPerpDir = normalize (cross rightArmDir [0,0,1])
        
        -- 左臂的四个顶点
        append verts (pointB + leftPerpDir * halfWidth)        -- 1: 左臂内侧底部
        append verts (pointB - leftPerpDir * halfWidth)        -- 2: 左臂外侧底部
        append verts (pointA + leftPerpDir * halfWidth)        -- 3: 左臂内侧顶部
        append verts (pointA - leftPerpDir * halfWidth)        -- 4: 左臂外侧顶部
        
        -- 右臂的四个顶点
        append verts (pointB - rightPerpDir * halfWidth)       -- 5: 右臂内侧底部
        append verts (pointB + rightPerpDir * halfWidth)       -- 6: 右臂外侧底部
        append verts (pointC - rightPerpDir * halfWidth)       -- 7: 右臂内侧顶部
        append verts (pointC + rightPerpDir * halfWidth)       -- 8: 右臂外侧顶部
        
        -- 创建面（三角形）
        -- 左臂的面
        append faces [1, 2, 3]  -- 左臂三角形1
        append faces [2, 4, 3]  -- 左臂三角形2
        
        -- 右臂的面
        append faces [5, 6, 7]  -- 右臂三角形1
        append faces [6, 8, 7]  -- 右臂三角形2
        
        -- 创建mesh对象
        local vShapeMesh = mesh vertices:verts faces:faces
        vShapeMesh.name = meshName
        
        -- 设置材质ID
        for i = 1 to vShapeMesh.numfaces do
        (
            setFaceMatID vShapeMesh i 1
        )
        
        update vShapeMesh
        return vShapeMesh
    )
    catch
    (
        print ("createSingleVShapeMesh 错误: " + getCurrentException())
        return undefined
    )
)

-------
-- 重新实现的中心模型生成算法（使用模板+实例化）
-------
-- 创建V字形导流线的3D网格模型
-- 参数：
--   vPos: V字形中心位置
--   vDir: V字形方向向量
--   leftBoundary: 左侧边界点（暂时保留，用于计算臂长）
--   rightBoundary: 右侧边界点（暂时保留，用于计算臂长）
--   leftSpline: 左侧边界样条线（暂时保留）
--   rightSpline: 右侧边界样条线（暂时保留）
--   lineThickness: 线条厚度
--   direction: 方向系数
--   fixedAngle: 固定角度
--   centerOffset: 中心底部顶点沿中心线向上的偏移距离
--   vTemplate: V字形模板对象（如果为undefined则创建新模板）
-- 返回：V字形网格对象
-------
fn createVShapeModel vPos vDir leftBoundary rightBoundary leftSpline rightSpline lineThickness direction fixedAngle centerOffset vTemplate:undefined = 
(
	try
	(
		-- 检查参数有效性
		if vPos == undefined or vDir == undefined then
		(
			print "createVShapeModel: 参数无效"
			return undefined
		)
		
		-- 计算V字形臂长（基于边界点距离）
        local leftDist = if leftBoundary != undefined then distance vPos leftBoundary else 300.0
        local rightDist = if rightBoundary != undefined then distance vPos rightBoundary else 300.0
        local armLength = (leftDist + rightDist) / 2.0
        
        -- 使用全局固定角度参数
        local angle = tgl_fixedAngle
        
        -- 如果没有提供模板，创建一个新的
        local template = vTemplate
        if template == undefined then
        (
            template = createVShapeTemplate armLength:armLength angle:angle thickness:lineThickness
            if template == undefined then
            (
                print "createVShapeModel: 无法创建V字形模板"
                return undefined
            )
        )
        
        -- 计算实例化位置和方向
        local pathDirection = if vDir != undefined then vDir else [1,0,0]
        pathDirection = pathDirection * direction  -- 应用方向系数
        
        -- 根据中心偏移调整位置（简化逻辑）
        local finalPosition = vPos + (normalize pathDirection) * centerOffset
        
        -- 实例化V字形到目标位置
        local instanceName = "VShapeInstance"
        local vShapeInstance = instanceVShapeAtPosition template finalPosition pathDirection instanceName
        
        -- 如果是临时创建的模板，删除它（只保留实例）
        if vTemplate == undefined and template != undefined then
        (
            delete template
        )
        
        return vShapeInstance
	)
	catch
	(
		print ("createVShapeModel 错误: " + getCurrentException())
		return undefined
	)
)

-------
-- 计算V字形位置和方向（使用双V字形算法）
-- 参数：
--   spline1: 第一条边界样条线
--   spline2: 第二条边界样条线
--   vSpacing: V字形间距
--   direction: 方向系数（1或-1）
--   centerOffset: 中心偏移（保持兼容性）
-- 返回：包含双V字形数据的数组
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
                
                -- 使用全局参数替代硬编码值
                local armLength = tgl_armLength      -- 使用全局臂长参数
                local acDistance = tgl_acDistance    -- 使用全局A、C距离参数  
                local vShapeDistance = tgl_vShapeDistance  -- 使用全局V字形间距参数
                
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
                                
                                -- 使用双V字形计算替代原有的单V字形计算
                                local dualVShapes = calculateDualVShapePoints vPos vDir armLength acDistance vShapeDistance
                                
                                -- 保持原有数据结构的兼容性，但添加双V字形数据
                                local calculatedAngle = tgl_fixedAngle
                                local adjustedVPos = vPos
                                
                                -- 扩展结果数据结构：#(位置, 方向, 左边界, 右边界, 角度, 双V字形数据)
                                append result #(adjustedVPos, vDir, leftBoundary, rightBoundary, calculatedAngle, dualVShapes)
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
-- 向后兼容的原始calculateVShapePositions函数（保留旧版本）
-------
fn calculateVShapePositionsLegacy spline1 spline2 vSpacing direction centerOffset =
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
                                
                                -- 使用固定角度模式
                                local calculatedAngle = tgl_fixedAngle
                                local adjustedVPos = vPos
                                
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
-- 高性能预览绘制函数 - 最小化重复计算
-------
fn drawTrafficGuidePreviewOptimal splines vSpacing lineThick direction centerOffset offsetDistance =
(
    try
    (
        if splines == undefined or splines.count < 2 then
            return false
            
        -- 检查样条线是否有效
        for spline in splines do
        (
            if not isValidNode spline then
                return false
        )
        
        local spline1 = splines[1]
        local spline2 = splines[2]
        
        -- 设置gw绘制参数
        gw.setTransform(matrix3 1)
        
        -- 预先计算一次样条线长度（避免重复调用）
        local spline1Length = curveLength spline1 1
        local spline2Length = curveLength spline2 1
        local avgLength = (spline1Length + spline2Length) / 2.0
        
        -- 1. 绘制封闭线段（起始连接线）- 简化计算
        try
        (
            local spline1Start = lengthInterp spline1 1 0.0
            local spline2Start = lengthInterp spline2 1 0.0
            
            -- 简化交点检测
            if (distance spline1Start spline2Start) > 50.0 then
            (
                gw.setColor #line (color 0 255 255)  -- 青色封闭线
                gw.polyline #(spline1Start, spline2Start) false
            )
        )
        catch
        (
            -- 静默处理封闭线错误
        )
        
        -- 2. 绘制中心偏移线段
        if offsetDistance > 0 and spline1Length > 0 and spline2Length > 0 then
        (
            try
            (
                local offsetParam1 = amax 0.0 (amin 1.0 (offsetDistance / spline1Length))
                local offsetParam2 = amax 0.0 (amin 1.0 (offsetDistance / spline2Length))
                
                local projectedStart = lengthInterp spline1 1 offsetParam1
                local projectedEnd = lengthInterp spline2 1 offsetParam2
                
                gw.setColor #line (color 255 0 0)  -- 红色中心偏移线段
                gw.polyline #(projectedStart, projectedEnd) false
            )
            catch
            (
                -- 静默处理偏移线错误
            )
        )
        
        -- 3. 简化的中心线（减少分段数）
        try
        (
            if avgLength > 0 then
            (
                local centerPoints = #()
                local centerLineSegments = 6  -- 减少到6段，提高性能
                
                for i = 0 to centerLineSegments do
                (
                    local param = i as float / centerLineSegments as float
                    
                    local pos1 = lengthInterp spline1 1 param
                    local pos2 = lengthInterp spline2 1 param
                    local centerPos = (pos1 + pos2) / 2.0
                    
                    append centerPoints centerPos
                )
                
                -- 绘制中心线路径
                if centerPoints.count > 1 then
                (
                    gw.setColor #line (color 150 150 150)  -- 浅灰色中心线
                    for i = 1 to (centerPoints.count - 1) do
                    (
                        gw.polyline #(centerPoints[i], centerPoints[i+1]) false
                    )
                )
            )
        )
        catch
        (
            -- 静默处理中心线错误
        )
        
        -- 4. 优化的双V字形绘制
        if avgLength > 0 and vSpacing > 0 then
        (
            -- 限制预览数量到更少
            local previewCount = amin 5 ((avgLength / vSpacing) as integer)  -- 减少到最多5个
            
            for i = 1 to previewCount do
            (
                local param = i as float / (previewCount + 1.0)  -- 均匀分布
                
                try
                (
                    -- 获取样条线上的位置
                    local pos1 = lengthInterp spline1 1 param
                    local pos2 = lengthInterp spline2 1 param  
                    local centerPos = (pos1 + pos2) / 2.0
                    
                    -- 简化的方向计算
                    local dir1 = lengthTangent spline1 1 param
                    local dir2 = lengthTangent spline2 1 param
                    local avgDir = normalize ((dir1 + dir2) / 2.0)
                    if direction < 0 then avgDir = -avgDir
                    
                    -- 使用简化的V字形计算（避免复杂三角函数）
                    local armLength = tgl_armLength
                    local halfWidth = tgl_acDistance / 2.0
                    local vOffset = tgl_vShapeDistance / 2.0
                    
                    -- 计算垂直方向
                    local perpDir = normalize (cross avgDir [0,0,1])
                    local offsetDir = [0,1,0]
                    
                    -- 第一个V字形（简化计算）
                    local center1 = centerPos - offsetDir * vOffset
                    local pointA1 = center1 - perpDir * halfWidth + avgDir * (armLength * 0.5)
                    local pointB1 = center1 - avgDir * (armLength * 0.5)
                    local pointC1 = center1 + perpDir * halfWidth + avgDir * (armLength * 0.5)
                    
                    gw.setColor #line tgl_previewColor  -- 黄色
                    gw.polyline #(pointA1, pointB1, pointC1) false
                    
                    -- 第二个V字形
                    local center2 = centerPos + offsetDir * vOffset
                    local pointA2 = center2 - perpDir * halfWidth + avgDir * (armLength * 0.5)
                    local pointB2 = center2 - avgDir * (armLength * 0.5)
                    local pointC2 = center2 + perpDir * halfWidth + avgDir * (armLength * 0.5)
                    
                    gw.setColor #line (color 255 165 0)  -- 橙色
                    gw.polyline #(pointA2, pointB2, pointC2) false
                    
                    -- 简化的中心标记
                    gw.setColor #line (color 255 0 0)  -- 红色标记点
                    local markerSize = 8.0
                    gw.polyline #([centerPos.x - markerSize, centerPos.y, centerPos.z], 
                                 [centerPos.x + markerSize, centerPos.y, centerPos.z]) false
                )
                catch
                (
                    -- 静默处理单个V字形错误
                )
            )
        )
        
        gw.enlargeUpdateRect #whole
        return true
    )
    catch
    (
        print ("优化预览绘制错误: " + getCurrentException())
        return false
    )
)
-------
-- 生成导流线几何体（使用模板+实例化架构）
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
        
        -- 使用双V字形算法创建所有V字形
        for i = 1 to vPositions.count do
        (
            local vData = vPositions[i]
            
            -- vData现在包含双V字形数据：#(#(pointA1, pointB1, pointC1), #(pointA2, pointB2, pointC2))
            if vData != undefined and vData.count == 2 then
            (
                -- 使用双V字形创建函数
                local dualVShapeMeshes = createDualVShapeModel vData lineThick ("TrafficGuide_" + i as string)
                
                -- 将创建的网格添加到对象集合中
                for mesh in dualVShapeMeshes do
                (
                    if mesh != undefined then
                        append createdObjects mesh
                )
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
            
            messageBox ("成功生成 " + vShapeCount as string + " 个V字形导流线(双V字形算法)和 " + closureCount as string + " 条封闭线段！") title:"完成"
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
-- 简化的预览系统
-------
fn initTrafficGuidePreview =
(
    try
    (
        if tgl_previewEnabled and tgl_selectedSplines.count >= 2 then
        (
            -- 使用高性能优化的预览函数
            drawTrafficGuidePreviewOptimal tgl_selectedSplines tgl_vSpacing tgl_lineThickness tgl_vDirection tgl_centerOffset tgl_offsetDistance
        )
    )
    catch
    (
        -- 静默处理错误，但输出到控制台便于调试
        print ("预览回调错误: " + getCurrentException())
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
rollout TrafficGuideLineRol "车道导流线生成器 v2.4.0" width:220 height:550
(
    groupBox 'grp1' "样条线选择" pos:[8,8] width:204 height:60 align:#left
    label 'lblInfo' "请选择两条样条线作为车道边界" pos:[15,25] width:190 height:15 align:#left
    button 'btnSelect' "选择样条线" pos:[15,40] width:100 height:25 align:#left
    label 'lblCount' "已选择: 0 条" pos:[125,45] width:80 height:15 align:#left
    
    groupBox 'grp2' "双V字形参数" pos:[8,75] width:204 height:200 align:#left
    spinner 'spnArmLength' "臂长度:" pos:[15,95] width:150 height:20 range:[50,2000,300] type:#worldunits scale:0.01
    spinner 'spnAcDistance' "底边宽度:" pos:[15,120] width:150 height:20 range:[50,600,200] type:#worldunits scale:0.01
    spinner 'spnVShapeDistance' "上下间距:" pos:[15,145] width:150 height:20 range:[50,1000,200] type:#worldunits scale:0.01
    spinner 'spnVSpacing' "V字间距:" pos:[15,170] width:150 height:20 range:[100,1000,200] type:#worldunits scale:0.01
    spinner 'spnLineThickness' "线条厚度:" pos:[15,195] width:150 height:20 range:[10,500,100] type:#worldunits scale:0.01
    spinner 'spnCenterOffset' "中点偏移:" pos:[15,220] width:150 height:20 range:[0,500,100] type:#worldunits scale:0.01
    spinner 'spnOffsetDistance' "偏移距离:" pos:[15,245] width:150 height:20 range:[0,500,30] type:#worldunits scale:0.01
    radiobuttons 'rdoDirection' "V字方向:" pos:[15,265] width:180 height:20 labels:#("正向", "反向") default:1
    
    groupBox 'grp3' "预览和生成" pos:[8,285] width:204 height:80 align:#left
    checkbox 'chkPreview' "显示预览" pos:[15,305] width:80 height:20 align:#left
    button 'btnGenerate' "生成导流线" pos:[50,330] width:120 height:30 align:#left
    
    groupBox 'grp4' "使用说明" pos:[8,375] width:204 height:165 align:#left
    label 'lblHelp1' "1. 选择两条定义车道边界的样条线" pos:[12,390] width:195 height:12 align:#left
    label 'lblHelp2' "2. 调整双V字形参数:" pos:[12,402] width:195 height:12 align:#left
    label 'lblHelp3' "   - 臂长度: V形臂长 (A到B点距离)" pos:[12,414] width:195 height:12 align:#left
    label 'lblHelp4' "   - 底边宽度: V形底边宽度 (A到C距离)" pos:[12,426] width:195 height:12 align:#left
    label 'lblHelp5' "   - 上下间距: 两个V形垂直间距" pos:[12,438] width:195 height:12 align:#left
    label 'lblHelp6' "   - V字间距: V形组之间的间隔" pos:[12,450] width:195 height:12 align:#left
    label 'lblHelp7' "3. 开启预览查看效果，然后生成" pos:[12,462] width:195 height:12 align:#left
    label 'lblHelp8' "注：使用双V字形算法保证一致性" pos:[12,474] width:195 height:12 align:#left
    label 'lblHelp9' "中点偏移：控制V形中心顶点位置" pos:[12,486] width:195 height:12 align:#left
    label 'lblHelp10' "已替换为VShapeGenerator的中心骨骼算法" pos:[12,498] width:195 height:12 align:#left
    
    -- 简化的预览更新函数
    fn updatePreview =
    (
        if chkPreview.checked and tgl_selectedSplines.count >= 2 then
        (
            -- 更新全局参数
            tgl_armLength = spnArmLength.value
            tgl_acDistance = spnAcDistance.value
            tgl_vShapeDistance = spnVShapeDistance.value
            tgl_vSpacing = spnVSpacing.value
            tgl_lineThickness = spnLineThickness.value
            tgl_centerOffset = spnCenterOffset.value
            tgl_offsetDistance = spnOffsetDistance.value
            tgl_vDirection = if rdoDirection.state == 1 then 1 else -1
            
            -- 直接触发视图重绘
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
        
        -- 初始化界面参数为全局变量值
        spnArmLength.value = tgl_armLength
        spnAcDistance.value = tgl_acDistance  
        spnVShapeDistance.value = tgl_vShapeDistance
        spnVSpacing.value = tgl_vSpacing
        spnLineThickness.value = tgl_lineThickness
        spnCenterOffset.value = tgl_centerOffset
        spnOffsetDistance.value = tgl_offsetDistance
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
    
    on spnArmLength changed val do updatePreview()
    on spnAcDistance changed val do updatePreview()
    on spnVShapeDistance changed val do updatePreview()
    on spnVSpacing changed val do updatePreview()
    on spnLineThickness changed val do updatePreview()
    on spnCenterOffset changed val do updatePreview()
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
            
            -- 收集参数（更新为双V字形参数）
            local armLength = spnArmLength.value
            local acDistance = spnAcDistance.value
            local vShapeDistance = spnVShapeDistance.value
            local vSpacing = spnVSpacing.value
            local lineThickness = spnLineThickness.value
            local centerOffset = spnCenterOffset.value
            local offsetDistance = spnOffsetDistance.value
            local direction = if rdoDirection.state == 1 then 1 else -1
            
            -- 更新全局参数
            tgl_armLength = armLength
            tgl_acDistance = acDistance
            tgl_vShapeDistance = vShapeDistance
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