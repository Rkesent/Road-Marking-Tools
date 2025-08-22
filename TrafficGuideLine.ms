-------
-- TrafficGuideLine v1.0.0 - 车道导流线生成器
-- 功能：基于两条样条线生成V字形导流线标记
-------

-- 全局变量
global tgl_previewColor = color 255 255 0  -- 黄色预览线条
global tgl_selectedSplines = #()
global tgl_previewEnabled = false
global tgl_vOffset = 200          -- V字形偏移量 (mm) - 0为直线，值越大角度越小
global tgl_vWidth = 400           -- V字形宽度 (mm)
global tgl_vSpacing = 1200        -- V字形间距 (mm)
global tgl_lineThickness = 100    -- 线条粗细 (mm)
global tgl_vDirection = 1         -- V字形方向 (1=正向, -1=反向)
global tgl_angleMode = false      -- 骨骼模式开关 (false=偏移量模式, true=固定骨骼模式)
global tgl_fixedAngle = 60.0      -- 固定角度值 (度)
-- 标准V字形参数
global tgl_standardVLength = 300.0   -- 标准V字形臂长 (mm)
global tgl_standardVAngle = 60.0     -- 标准开合角度 (度)
global tgl_standardVWidth = 100.0    -- 标准线条宽度 (mm)

-------
-- 创建标准V字形几何体（固定条状三角形）
-------
fn createStandardVShape centerPos direction lineWidth =
(
    try
    (
        -- 使用全局标准参数
        local vLength = tgl_standardVLength
        local vAngle = tgl_standardVAngle
        local vWidth = if lineWidth != undefined then lineWidth else tgl_standardVWidth
        
        -- 计算标准V字形的几何参数
        local halfAngleRad = degToRad (vAngle / 2.0)
        local halfWidth = vWidth / 2.0
        
        -- 计算V字形的标准端点（相对于中心点）
        -- 修正：直接使用半角计算左右臂的方向
        local forwardDir = [1, 0, 0]  -- 标准前进方向
        
        -- V字形的三个关键点（相对坐标）
        local centerBottom = [0, 0, 0]
        
        -- 计算左右臂的方向向量（从中心点向外）
        -- 左臂：向前进方向旋转-halfAngle（逆时针）
        local leftAngleRad = -halfAngleRad
        local leftDir = [cos leftAngleRad, sin leftAngleRad, 0]
        local leftTop = leftDir * vLength
        
        -- 右臂：向前进方向旋转+halfAngle（顺时针）  
        local rightAngleRad = halfAngleRad
        local rightDir = [cos rightAngleRad, sin rightAngleRad, 0]
        local rightTop = rightDir * vLength
        
        -- 创建V字形几何体
        local verts = #()
        
        -- 左臂四边形顶点
        local leftDir = normalize leftTop
        local leftPerp = normalize (cross leftDir [0,0,1])
        append verts (centerBottom + leftPerp * halfWidth)
        append verts (centerBottom - leftPerp * halfWidth)  
        append verts (leftTop - leftPerp * halfWidth)
        append verts (leftTop + leftPerp * halfWidth)
        
        -- 右臂四边形顶点
        local rightDir = normalize rightTop  
        local rightPerp = normalize (cross rightDir [0,0,1])
        append verts (centerBottom + rightPerp * halfWidth)
        append verts (centerBottom - rightPerp * halfWidth)
        append verts (rightTop - rightPerp * halfWidth)
        append verts (rightTop + rightPerp * halfWidth)
        
        -- 创建面
        local faces = #()
        -- 左臂面
        append faces [1,2,3]
        append faces [3,4,1]
        -- 右臂面  
        append faces [5,6,7]
        append faces [7,8,5]
        
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
-- 检测两条样条线的首点是否相交，并计算封闭信息
-------
fn analyzeSplineIntersection spline1 spline2 =
(
    local result = #()
    local intersectionTolerance = 50.0  -- 相交判定容差（系统单位）
    
    -- 获取两条样条线的首点（起点）和尾点（终点）
    local spline1Start = lengthInterp spline1 1 0.0  -- 样条线1的首点
    local spline1End = lengthInterp spline1 1 1.0    -- 样条线1的尾点
    local spline2Start = lengthInterp spline2 1 0.0  -- 样条线2的首点
    local spline2End = lengthInterp spline2 1 1.0    -- 样条线2的尾点
    
    -- 检查首点是否相交（两条样条线的起点是否接近）
    local startIntersect = (distance spline1Start spline2Start) < intersectionTolerance
    -- 检查尾点是否相交（两条样条线的终点是否接近）
    local endIntersect = (distance spline1End spline2End) < intersectionTolerance
    
    -- 返回结果：#(首点相交, 尾点相交, 首点封闭线, 尾点封闭线)
    local startClosureLine = undefined
    local endClosureLine = undefined
    
    -- 只有在首点不相交时才创建首点封闭线
    if not startIntersect then
        startClosureLine = #(spline1Start, spline2Start)
    
    -- 只有在尾点不相交时才创建尾点封闭线  
    if not endIntersect then
        endClosureLine = #(spline1End, spline2End)
    
    return #(startIntersect, endIntersect, startClosureLine, endClosureLine)
)

-------
-- 创建封闭线段的3D模型
-------
fn createClosureLine startPoint endPoint lineThickness =
(
    try
    (
        if startPoint == undefined or endPoint == undefined then
            return undefined
            
        -- 计算线段方向和长度
        local lineVector = endPoint - startPoint
        local lineLength = length lineVector
        
        if lineLength < 1.0 then  -- 太短的线段跳过
            return undefined
        
        local lineDir = normalize lineVector
        local halfThickness = lineThickness / 2.0
        
        -- 计算垂直于线段的方向（在XY平面上）
        -- 使用右手坐标系，确保垂直方向正确
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
        newMesh.name = "ClosureLine_" + (random 1000 9999) as string
        
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
        print ("createClosureLine 错误: " + getCurrentException())
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
fn createVShapeModel vPos vDir leftBoundary rightBoundary lineThickness vOffset direction angleMode fixedAngle spline1 spline2 pathParam = 
(
	try
	(
		-- 检查参数有效性
		if vPos == undefined or vDir == undefined or leftBoundary == undefined or rightBoundary == undefined then
		(
			print "createVShapeModel: 参数无效"
			return undefined
		)
		
		-- 计算V字形的基本几何
		local centerLine = vPos
		local leftTop = leftBoundary
		local rightTop = rightBoundary
		local centerBottom = undefined
		
		-- 确保所有点在同一水平面上
		leftTop.z = centerLine.z
		rightTop.z = centerLine.z
		
		-- 根据模式计算V字形几何
		if angleMode then
		(
			-- 固定骨骼模式：使用标准V字形
			-- 不需要复杂计算，直接使用标准形状
			centerBottom = centerLine
			leftTop = centerLine  -- 这些参数在标准模式下不使用
			rightTop = centerLine
		)
		else
		(
			-- 偏移量模式：调整中心点位置
			local midPoint = (leftTop + rightTop) / 2.0
			local toMidDir = normalize (centerLine - midPoint)
			toMidDir = toMidDir * direction
			centerBottom = centerLine + toMidDir * vOffset
		)
		
		-- 根据模式创建不同的几何体
		if angleMode then
		(
			-- 固定骨骼模式：创建标准V字形
			local pathDirection = if vDir != undefined then vDir else [1,0,0]
			pathDirection = pathDirection * direction  -- 应用方向系数
			local standardVShape = createStandardVShape centerLine pathDirection lineThickness
			return standardVShape
		)
		else
		(
			-- 偏移量模式：使用原来的动态计算方式
			-- 重新计算到左右顶点的向量（从新的中心底部点）
			local leftVector = leftTop - centerBottom
			local rightVector = rightTop - centerBottom
			
			-- 计算线条厚度的一半
			local halfThickness = lineThickness / 2.0
			
			-- 为左臂创建四边形
			local leftArmVerts = #()
			local leftDir = normalize leftVector
			local leftPerp = normalize (cross leftDir [0,0,1])
			
			-- 左臂的四个顶点（从中心底部到左顶点）
			append leftArmVerts (centerBottom + leftPerp * halfThickness)
			append leftArmVerts (centerBottom - leftPerp * halfThickness)
			append leftArmVerts (leftTop - leftPerp * halfThickness)
			append leftArmVerts (leftTop + leftPerp * halfThickness)
			
			-- 为右臂创建四边形
			local rightArmVerts = #()
			local rightDir = normalize rightVector
			local rightPerp = normalize (cross rightDir [0,0,1])
			
			-- 右臂的四个顶点（从中心底部到右顶点）
			append rightArmVerts (centerBottom + rightPerp * halfThickness)
			append rightArmVerts (centerBottom - rightPerp * halfThickness)
			append rightArmVerts (rightTop - rightPerp * halfThickness)
			append rightArmVerts (rightTop + rightPerp * halfThickness)
			
			-- 创建网格对象
			local meshVerts = leftArmVerts + rightArmVerts
			local meshFaces = #()
			
			-- 左臂面（顶点索引1-4）
			append meshFaces [1,2,3]
			append meshFaces [3,4,1]
			
			-- 右臂面（顶点索引5-8）
			append meshFaces [5,6,7]
			append meshFaces [7,8,5]
			
			-- 创建mesh对象
			local newMesh = mesh vertices:meshVerts faces:meshFaces
			newMesh.name = "VShape_" + (random 1000 9999) as string
			
			-- 设置材质ID
			for i = 1 to newMesh.numfaces do
			(
				setFaceMatID newMesh i 1
			)
			
			-- 更新网格
			update newMesh
			
			return newMesh
		)
	)
	catch
	(
		print ("createVShapeModel 错误: " + getCurrentException())
		return undefined
	)
)

-------
-- 计算导流线V字形位置（考虑首点和尾点封闭区域）
-------
fn calculateVShapePositions spline1 spline2 vOffset vSpacing direction =
(
    local result = #()
    local centerPoints = calculateCenterPath spline1 spline2
    
    -- 分析样条线相交情况
    local intersectionInfo = analyzeSplineIntersection spline1 spline2
    local startIntersect = intersectionInfo[1]  -- 首点是否相交
    local endIntersect = intersectionInfo[2]    -- 尾点是否相交
    
    if centerPoints.count > 1 then
    (
        -- 计算中心路径的总长度
        local totalLength = 0
        for i = 2 to centerPoints.count do
        (
            totalLength += distance centerPoints[i-1] centerPoints[i]
        )
        
        if totalLength > vOffset then
        (
            -- 计算需要避开的封闭区域长度
            local closureBuffer = vSpacing * 0.5  -- 封闭区域缓冲距离
            
            -- 只有在对应位置有封闭线段时才设置缓冲区域
            local startOffset = if startIntersect then 0 else closureBuffer  -- 首点未相交时避让
            local endOffset = if endIntersect then 0 else closureBuffer      -- 尾点未相交时避让
            
            -- 有效的V字形生成区域（从首点算起）
            local validStartDist = startOffset
            local validEndDist = totalLength - endOffset
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
                                
                                append result #(vPos, vDir, leftBoundary, rightBoundary)
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
fn drawTrafficGuidePreview splines vOffset vWidth vSpacing lineThick direction angleMode fixedAngle =
(
    if splines.count >= 2 then
    (
        gw.setTransform(matrix3 1)
        gw.setColor #line tgl_previewColor
        
        local spline1 = splines[1]
        local spline2 = splines[2]
        
        -- 分析相交情况
        local intersectionInfo = analyzeSplineIntersection spline1 spline2
        local startIntersect = intersectionInfo[1]
        local endIntersect = intersectionInfo[2]
        local startClosureLine = intersectionInfo[3]
        local endClosureLine = intersectionInfo[4]
        
        -- 绘制封闭线段
        gw.setColor #line (color 0 255 255)  -- 青色封闭线
        if startClosureLine != undefined then
        (
            gw.polyline #(startClosureLine[1], startClosureLine[2]) false
        )
        if endClosureLine != undefined then
        (
            gw.polyline #(endClosureLine[1], endClosureLine[2]) false
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
        )
        
        -- 计算并绘制V字形位置点
        local vPositions = calculateVShapePositions spline1 spline2 vOffset vSpacing direction
        
        gw.setColor #line tgl_previewColor
        for vData in vPositions do
        (
            local vPos = vData[1]
            local vDir = vData[2]
            local leftBoundary = vData[3]
            local rightBoundary = vData[4]
            
            -- 计算路径参数（用于边界检查）
            local totalLength = 0
            for j = 2 to centerPoints.count do
            (
                totalLength += distance centerPoints[j-1] centerPoints[j]
            )
            local pathParam = if totalLength > 0 then (distance centerPoints[1] vPos) / totalLength else 0.0
            
            -- 根据模式计算V字形几何
            local centerBottom
            local leftTop = leftBoundary
            local rightTop = rightBoundary
            local centerLine = vPos
            
            -- 确保在同一水平面
            leftTop.z = centerLine.z
            rightTop.z = centerLine.z
            
            if angleMode then
            (
                -- 固定骨骼模式：绘制标准V字形预览
                local pathDirection = if vDir != undefined then vDir else [1,0,0]
                pathDirection = pathDirection * direction
                
                -- 计算标准V字形的端点用于预览
                local vLength = tgl_standardVLength  
                local vAngle = tgl_standardVAngle
                local halfAngleRad = degToRad (vAngle / 2.0)
                
                -- 计算相对于路径方向的左右端点
                local forwardDir = normalize pathDirection
                
                -- 修正：使用旋转矩阵计算正确的V字形端点
                -- 左臂：相对于前进方向逆时针旋转半角
                local leftAngleRad = -halfAngleRad  
                local leftDir = [forwardDir.x * cos leftAngleRad - forwardDir.y * sin leftAngleRad,
                                forwardDir.x * sin leftAngleRad + forwardDir.y * cos leftAngleRad,
                                0]
                local leftEnd = centerLine + leftDir * vLength
                
                -- 右臂：相对于前进方向顺时针旋转半角
                local rightAngleRad = halfAngleRad
                local rightDir = [forwardDir.x * cos rightAngleRad - forwardDir.y * sin rightAngleRad,
                                 forwardDir.x * sin rightAngleRad + forwardDir.y * cos rightAngleRad, 
                                 0]
                local rightEnd = centerLine + rightDir * vLength
                
                centerBottom = centerLine
                leftTop = leftEnd
                rightTop = rightEnd
            )
            else
            (
                -- 偏移量模式：调整中心点位置
                local midPoint = (leftTop + rightTop) / 2.0
                local toMidDir = normalize (centerLine - midPoint)
                toMidDir = toMidDir * direction
                centerBottom = centerLine + toMidDir * vOffset
                
                -- 检查中心开合角度，小于30度时跳过预览（仅偏移量模式）
                local vAngle = calculateVShapeAngle leftBoundary rightBoundary centerBottom
                if vAngle < 30.0 then continue
            )
            
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
            local markerSize = 50.0
            gw.polyline #([centerBottom.x - markerSize, centerBottom.y, centerBottom.z], [centerBottom.x + markerSize, centerBottom.y, centerBottom.z]) false
            gw.polyline #([centerBottom.x, centerBottom.y - markerSize, centerBottom.z], [centerBottom.x, centerBottom.y + markerSize, centerBottom.z]) false
        )
        
        gw.enlargeUpdateRect #whole
        gw.updateScreen()
    )
)

-------
-- 生成导流线几何体（包含封闭线段）
-------
fn generateTrafficGuideLine splines vOffset vSpacing lineThick direction angleMode fixedAngle =
(
    if splines.count < 2 then
    (
        messageBox "请选择两条样条线！" title:"错误"
        return undefined
    )
    
    local spline1 = splines[1]
    local spline2 = splines[2]
    
    -- 分析相交情况
    local intersectionInfo = analyzeSplineIntersection spline1 spline2
    local startIntersect = intersectionInfo[1]
    local endIntersect = intersectionInfo[2]
    local startClosureLine = intersectionInfo[3]
    local endClosureLine = intersectionInfo[4]
    
    -- 计算V字形位置
    local vPositions = calculateVShapePositions spline1 spline2 vOffset vSpacing direction
    
    try
    (
        -- 创建组来管理所有对象
        local mainGroup = group name:("TrafficGuideLine_" + (random 1000 9999) as string)
        local createdObjects = #()
        
        -- 创建封闭线段
        if startClosureLine != undefined then
        (
            local startClosure = createClosureLine startClosureLine[1] startClosureLine[2] lineThick
            if startClosure != undefined then
                append createdObjects startClosure
        )
        
        if endClosureLine != undefined then
        (
            local endClosure = createClosureLine endClosureLine[1] endClosureLine[2] lineThick
            if endClosure != undefined then
                append createdObjects endClosure
        )
        
        -- 创建V字形模型
        for i = 1 to vPositions.count do
        (
            local vData = vPositions[i]
            local vPos = vData[1]
            local vDir = vData[2]  
            local leftBoundary = vData[3]
            local rightBoundary = vData[4]
            
            -- 计算路径参数（用于边界检查）
            local totalLength = 0
            local centerPoints = calculateCenterPath spline1 spline2
            for j = 2 to centerPoints.count do
            (
                totalLength += distance centerPoints[j-1] centerPoints[j]
            )
            local pathParam = if totalLength > 0 then (distance centerPoints[1] vPos) / totalLength else 0.0
            
            -- 检查中心开合角度，小于30度时跳过（仅在偏移量模式下检查）
            if not angleMode then
            (
                local vAngle = calculateVShapeAngle leftBoundary rightBoundary vPos
                if vAngle < 30.0 then continue
            )
            
            -- 创建单个V字形模型，传递所有必要参数
            local vShapeMesh = createVShapeModel vPos vDir leftBoundary rightBoundary lineThick vOffset direction angleMode fixedAngle spline1 spline2 pathParam
            
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
            
            local closureCount = 0
            if startClosureLine != undefined then closureCount += 1
            if endClosureLine != undefined then closureCount += 1
            local vShapeCount = createdObjects.count - closureCount
            
            local modeText = if angleMode then "固定骨骼" else "偏移量"
            messageBox ("成功生成 " + vShapeCount as string + " 个V字形导流线(" + modeText + ")和 " + closureCount as string + " 条封闭线段！") title:"完成"
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
            drawTrafficGuidePreview tgl_selectedSplines tgl_vOffset tgl_vWidth tgl_vSpacing tgl_lineThickness tgl_vDirection tgl_angleMode tgl_fixedAngle
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
rollout TrafficGuideLineRol "车道导流线生成器 v1.0.0" width:220 height:425
(
    groupBox 'grp1' "样条线选择" pos:[8,8] width:204 height:60 align:#left
    label 'lblInfo' "请选择两条样条线作为车道边界" pos:[15,25] width:190 height:15 align:#left
    button 'btnSelect' "选择样条线" pos:[15,40] width:100 height:25 align:#left
    label 'lblCount' "已选择: 0 条" pos:[125,45] width:80 height:15 align:#left
    
    groupBox 'grp2' "V字形参数" pos:[8,75] width:204 height:175 align:#left
    radiobuttons 'rdoMode' "计算模式:" pos:[15,95] width:180 height:35 labels:#("偏移量模式", "固定骨骼模式") default:1
    spinner 'spnVOffset' "V字偏移:" pos:[15,135] width:150 height:20 range:[0,10000,200] type:#worldunits scale:0.01 enabled:true
    -- 标准V字形参数
    spinner 'spnStandardLength' "标准臂长:" pos:[15,160] width:150 height:20 range:[100,800,300] type:#worldunits scale:0.01 enabled:false
    spinner 'spnStandardAngle' "标准角度:" pos:[15,185] width:150 height:20 range:[15,120,60] type:#float scale:0.1 enabled:false
    spinner 'spnVSpacing' "V字间距:" pos:[15,210] width:150 height:20 range:[100,1000,200] type:#worldunits scale:0.01
    spinner 'spnLineThickness' "线条厚度:" pos:[15,235] width:150 height:20 range:[10,500,100] type:#worldunits scale:0.01
    radiobuttons 'rdoDirection' "V字方向:" pos:[15,255] width:180 height:20 labels:#("正向", "反向") default:1
    
    groupBox 'grp3' "预览和生成" pos:[8,260] width:204 height:80 align:#left
    checkbox 'chkPreview' "显示预览" pos:[15,280] width:80 height:20 align:#left
    button 'btnGenerate' "生成导流线" pos:[50,305] width:120 height:30 align:#left
    
    groupBox 'grp4' "使用说明" pos:[8,350] width:204 height:65 align:#left
    label 'lblHelp1' "1. 选择两条定义车道边界的样条线" pos:[12,365] width:195 height:12 align:#left
    label 'lblHelp2' "2. 选择计算模式和调整参数" pos:[12,377] width:195 height:12 align:#left
    label 'lblHelp3' "3. 开启预览查看效果，然后生成" pos:[12,389] width:195 height:12 align:#left
    label 'lblHelp4' "注：固定骨骼模式使用标准V字形" pos:[12,401] width:195 height:12 align:#left
    
    -- 更新预览
    fn updatePreview =
    (
        if chkPreview.checked and tgl_selectedSplines.count >= 2 then
        (
            tgl_vOffset = spnVOffset.value
            tgl_standardVLength = spnStandardLength.value
            tgl_standardVAngle = spnStandardAngle.value
            tgl_vSpacing = spnVSpacing.value
            tgl_lineThickness = spnLineThickness.value
            tgl_vDirection = if rdoDirection.state == 1 then 1 else -1
            tgl_angleMode = (rdoMode.state == 2)
            redrawviews()
        )
    )
    
    -- 更新控件启用状态
    fn updateControls =
    (
        local isAngleMode = (rdoMode.state == 2)
        spnVOffset.enabled = not isAngleMode
        spnStandardLength.enabled = isAngleMode
        spnStandardAngle.enabled = isAngleMode
        tgl_angleMode = isAngleMode
    )
    
    -- 界面事件
    on TrafficGuideLineRol open do
    (
        unregisterPreview()
        tgl_previewEnabled = false
        chkPreview.checked = false
        tgl_selectedSplines = #()
        lblCount.text = "已选择: 0 条"
        updateControls()
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
    
    on rdoMode changed state do
    (
        updateControls()
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
    
    on spnVOffset changed val do updatePreview()
    on spnStandardLength changed val do updatePreview()
    on spnStandardAngle changed val do updatePreview() 
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
            
            -- 收集参数
            local vOffset = spnVOffset.value
            local standardLength = spnStandardLength.value
            local standardAngle = spnStandardAngle.value
            local vSpacing = spnVSpacing.value
            local lineThickness = spnLineThickness.value
            local direction = if rdoDirection.state == 1 then 1 else -1
            local angleMode = (rdoMode.state == 2)
            
            -- 更新全局标准参数
            tgl_standardVLength = standardLength
            tgl_standardVAngle = standardAngle
            
            -- 生成导流线
            local result = generateTrafficGuideLine tgl_selectedSplines vOffset vSpacing lineThickness direction angleMode standardAngle
            
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