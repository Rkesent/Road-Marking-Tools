-------
-- VShapeGenerator v1.0.0 - V字形线段生成器
-- 功能：生成可调节的V字形线段并实例化到样条线上
-------

-- 清除之前的函数定义以避免冲突
try (createVShapeGeometry = undefined) catch()
try (calculateVShapePoints = undefined) catch()
try (instanceVShapeOnSpline = undefined) catch()
try (convertSplineToSurface = undefined) catch()
try (generateSplineSurface = undefined) catch()

-- Loading VShapeGenerator script

-- 全局变量
global vsg_previewColor = color 255 128 0  -- 橙色预览线条
global vsg_selectedSpline = undefined
global vsg_previewEnabled = false
global vsg_armLength = 300.0      -- V字形臂长 (mm)
global vsg_acDistance = 200.0     -- A、C两点间距离 (mm)
global vsg_instanceSpacing = 500.0 -- 实例间距 (mm)
global vsg_vShapeDistance = 200.0 -- 两个V字形之间的距离 (mm)
global vsg_surfaceWidth = 100.0   -- 片面宽度 (mm)
global vsg_subdivisions = 20      -- 片面细分数
global vsg_previewObjects = #()   -- 预览对象数组

-------
-- 计算单个V字形的三个关键点（A、B、C）
-- 参数：
--   centerPos: B点位置（顶点中心）
--   direction: 前进方向向量
--   armLength: 臂长（A、C到B的距离）
--   acDistance: A、C两点间的距离
-- 返回：#(pointA, pointB, pointC)
-------
fn calculateSingleVShapePoints centerPos direction armLength acDistance =
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
fn calculateDualVShapePoints centerPos direction armLength acDistance vShapeDistance =
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
        local vShape1 = calculateSingleVShapePoints centerPos1 direction armLength acDistance
        
        -- 计算第二个V字形的点
        local vShape2 = calculateSingleVShapePoints centerPos2 direction armLength acDistance
        
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
-- 兼容性函数：保持原有接口，默认生成双V字形
-- 参数：
--   centerPos: B点位置（顶点中心）
--   direction: 前进方向向量
--   armLength: 臂长（A、C到B的距离）
--   acDistance: A、C两点间的距离
-- 返回：#(#(pointA1, pointB1, pointC1), #(pointA2, pointB2, pointC2))
-------
fn calculateVShapePoints centerPos direction armLength acDistance =
(
    -- 默认使用200单位的V字形间距
    return calculateDualVShapePoints centerPos direction armLength acDistance 200.0
)

-------
-- 创建单个V字形线段
-- 参数：
--   points: #(pointA, pointB, pointC) 三个顶点
--   objName: 对象名称
-- 返回：创建的线段对象
-------
fn createSingleVShapeLines points objName:"VShape" =
(
    try
    (
        local pointA = points[1]
        local pointB = points[2] 
        local pointC = points[3]
        
        -- 创建V字形线段
        local vShapeSpline = splineShape()
        vShapeSpline.name = objName
        
        -- 添加新的样条线到形状中
        addNewSpline vShapeSpline
        
        -- 添加顶点到样条线
        addKnot vShapeSpline 1 #corner #line pointA
        addKnot vShapeSpline 1 #corner #line pointB  
        addKnot vShapeSpline 1 #corner #line pointC
        
        -- 更新形状
        updateShape vShapeSpline
        
        return vShapeSpline
    )
    catch
    (
        return undefined
    )
)

-------
-- 创建双V字形线段
-- 参数：
--   dualPoints: #(#(pointA1, pointB1, pointC1), #(pointA2, pointB2, pointC2)) 两个V字形的点集
--   objName: 对象名称前缀
-- 返回：包含两个V字形线段的数组
-------
fn createDualVShapeLines dualPoints objName:"DualVShape" =
(
    try
    (
        local resultObjects = #()
        
        -- 创建第一个V字形
        local vShape1 = createSingleVShapeLines dualPoints[1] objName:(objName + "_1")
        if vShape1 != undefined then
            append resultObjects vShape1
        
        -- 创建第二个V字形
        local vShape2 = createSingleVShapeLines dualPoints[2] objName:(objName + "_2")
        if vShape2 != undefined then
            append resultObjects vShape2
        
        return resultObjects
    )
    catch
    (
        return #()
    )
)

-------
-- 兼容性函数：保持原有接口，现在创建双V字形
-- 参数：
--   points: #(#(pointA1, pointB1, pointC1), #(pointA2, pointB2, pointC2)) 双V字形点集
--   objName: 对象名称
-- 返回：包含两个V字形线段的数组
-------
fn createVShapeLines points objName:"VShape" =
(
    -- 检查输入格式
    if points.count == 2 and classof points[1] == Array and classof points[2] == Array then
    (
        -- 新格式：双V字形点集
        return createDualVShapeLines points objName
    )
    else if points.count == 3 then
    (
        -- 旧格式：单个V字形点集，转换为双V字形格式
        local singleVShape = createSingleVShapeLines points objName
        if singleVShape != undefined then
            return #(singleVShape)
        else
            return #()
    )
    else
    (
        return #()
    )
)

-------
-- 将样条线转换为片面模型
-- 参数：
--   splineObj: 目标样条线对象
--   width: 片面宽度
--   subdivisions: 细分数量
--   objName: 对象名称
-- 返回：创建的mesh对象
-------
fn convertSplineToSurface splineObj width subdivisions objName:"SplineSurface" =
(
    try
    (
        if splineObj == undefined or superclassof splineObj != Shape then
        (
            messageBox "选择的对象不是有效的样条线！" title:"错误"
            return undefined
        )
        
        -- 检查样条线是否包含至少一个样条线
        if numSplines splineObj == 0 then
        (
            messageBox "样条线对象为空！" title:"错误"
            return undefined
        )
        
        local halfWidth = width / 2.0
        local verts = #()
        local faces = #()
        
        -- 沿样条线采样点
        for i = 0 to subdivisions do
        (
            local param = i as float / subdivisions as float
            if param > 1.0 then param = 1.0
            
            -- 确保样条线索引有效
             local splineIndex = 1
             if numSplines splineObj > 0 then
             (
                 -- 获取样条线上的位置和切线方向
                 local currentPos = lengthInterp splineObj splineIndex param
                 local tangentDir = normalize (lengthTangent splineObj splineIndex param)
                 
                 -- 计算垂直方向（在XY平面内）
                 local perpDir = normalize (cross tangentDir [0,0,1])
                 
                 -- 创建左右边界点
                 local leftPoint = currentPos - perpDir * halfWidth
                 local rightPoint = currentPos + perpDir * halfWidth
                 
                 append verts leftPoint
                 append verts rightPoint
             )
        )
        
        -- 创建面片（四边形分解为两个三角形）
        for i = 1 to subdivisions do
        (
            local baseIndex = (i - 1) * 2 + 1
            local nextIndex = baseIndex + 2
            
            -- 第一个三角形
            append faces [baseIndex, baseIndex + 1, nextIndex]
            -- 第二个三角形
            append faces [baseIndex + 1, nextIndex + 1, nextIndex]
        )
        
        -- 创建mesh对象
        local surfaceMesh = mesh vertices:verts faces:faces
        surfaceMesh.name = objName
        
        -- 设置材质ID
        for i = 1 to surfaceMesh.numfaces do
        (
            setFaceMatID surfaceMesh i 1
        )
        
        -- 更新mesh
        update surfaceMesh
        
        return surfaceMesh
    )
    catch
    (
        return undefined
    )
)

-------
-- 在样条线上实例化双V字形线段
-- 参数：
--   splineObj: 目标样条线对象
--   armLength: V字形臂长
--   acDistance: A、C两点间距离
--   spacing: 实例间距
--   vShapeDistance: 两个V字形之间的距离（可选，默认200）
-- 返回：创建的V字形线段对象数组
-------
fn instanceVShapeOnSpline splineObj armLength acDistance spacing vShapeDistance:200.0 =
(
    local resultObjects = #()
    
    try
    (
        if splineObj == undefined or superclassof splineObj != Shape then
        (
            messageBox "选择的对象不是有效的样条线！" title:"错误"
            return resultObjects
        )
        
        -- 检查样条线是否包含至少一个样条线
        if numSplines splineObj == 0 then
        (
            messageBox "样条线对象为空！" title:"错误"
            return resultObjects
        )
        
        -- 获取样条线长度
        local splineLength = curveLength splineObj 1
        
        if splineLength <= 0 or spacing <= 0 then
        (
            return resultObjects
        )
        
        -- 计算实例数量
        local numInstances = (splineLength / spacing) as integer
        if numInstances <= 0 then numInstances = 1
        
        -- 沿样条线创建双V字形实例
        for i = 1 to numInstances do
        (
            -- 计算当前距离位置
            local currentDistance = (i - 1) * spacing
            if currentDistance > splineLength then currentDistance = splineLength
            
            -- 计算参数值（0.0 到 1.0）
            local param = currentDistance / splineLength
            if param > 1.0 then param = 1.0
            
            -- 确保样条线索引有效
             local splineIndex = 1
             if numSplines splineObj > 0 then
             (
                 -- 获取样条线上的位置和切线方向
                 local currentPos = lengthInterp splineObj splineIndex param
                 local tangentDir = lengthTangent splineObj splineIndex param
                 
                 -- 计算双V字形的点集
                 local dualVPoints = calculateDualVShapePoints currentPos tangentDir armLength acDistance vShapeDistance
                 
                 -- 创建双V字形线段
                 local vShapeObjects = createDualVShapeLines dualVPoints objName:("DualVShape_" + i as string)
                 
                 -- 将创建的对象添加到结果数组
                 for obj in vShapeObjects do
                 (
                     if obj != undefined then
                         append resultObjects obj
                 )
             )
        )
    )
    catch
    (
        -- 错误处理
    )
    
    return resultObjects
)

-------
-- 预览绘制函数（内部使用，带参数）
-------
fn drawVShapePreviewInternal splineObj armLength acDistance spacing vShapeDistance =
(
    -- 清空预览对象数组（不再需要存储对象）
    vsg_previewObjects = #()
    
    if splineObj == undefined or not vsg_previewEnabled then
        return()
    
    -- 检查样条线对象有效性
    if superclassof splineObj != Shape or numSplines splineObj == 0 then
        return()
    
    try
    (
        -- 设置gw绘制参数（在所有循环之前设置一次）
        gw.setTransform(matrix3 1)
        gw.setColor #line vsg_previewColor
        
        -- 获取样条线长度
        local splineLength = curveLength splineObj 1
        
        if splineLength <= 0 or spacing <= 0 then
            return()
        
        -- 计算预览实例数量（限制数量以提高性能）
        local numInstances = (splineLength / spacing) as integer
        if numInstances > 20 then numInstances = 20  -- 限制预览数量
        if numInstances <= 0 then numInstances = 1
        
        -- 绘制预览V字形线段
        for i = 1 to numInstances do
        (
            -- 计算当前距离位置
            local currentDistance = (i - 1) * spacing
            if currentDistance > splineLength then currentDistance = splineLength
            
            -- 计算参数值（0.0 到 1.0）
            local param = currentDistance / splineLength
            if param > 1.0 then param = 1.0
            
            -- 确保样条线索引有效
            local splineIndex = 1
            if numSplines splineObj > 0 then
            (
                -- 获取样条线上的位置和方向
                local currentPos = lengthInterp splineObj splineIndex param
                local tangentDir = lengthTangent splineObj splineIndex param
                
                -- 计算双V字形点
                local dualVPoints = calculateDualVShapePoints currentPos tangentDir armLength acDistance vShapeDistance
                
                -- 绘制第一个V字形
                local vPoints1 = dualVPoints[1]
                gw.polyline #(vPoints1[1], vPoints1[2], vPoints1[3]) false
                
                -- 绘制第二个V字形
                local vPoints2 = dualVPoints[2]
                gw.polyline #(vPoints2[1], vPoints2[2], vPoints2[3]) false
            )
        )
        
        -- 标记需要更新的区域（让3ds Max处理实际的屏幕更新）
        gw.enlargeUpdateRect #whole
    )
    catch
    (
        -- 错误处理
    )
)

-------
-- 预览回调函数（无参数，用于registerRedrawViewsCallback）
-------
fn drawVShapePreview =
(
    if vsg_previewEnabled and vsg_selectedSpline != undefined then
    (
        drawVShapePreviewInternal vsg_selectedSpline vsg_armLength vsg_acDistance vsg_instanceSpacing vsg_vShapeDistance
    )
)

-------
-- 注册预览回调
-------
fn registerVShapePreview =
(
    unregisterRedrawViewsCallback drawVShapePreview
    registerRedrawViewsCallback drawVShapePreview
)

-------
-- 注销预览回调
-------
fn unregisterVShapePreview =
(
    unregisterRedrawViewsCallback drawVShapePreview
    -- 清空预览对象数组（gw绘制不需要删除对象）
    vsg_previewObjects = #()
)

-------
-- 基于当前预览参数生成V字形线段函数
-------
fn generateVShapesFromPreview =
(
    if not vsg_previewEnabled or vsg_selectedSpline == undefined then
    (
        messageBox "请先启用预览并选择样条线！" title:"错误"
        return undefined
    )
    
    -- 使用当前的全局参数生成V字形线段
    return generateVShapes vsg_selectedSpline vsg_armLength vsg_acDistance vsg_instanceSpacing vShapeDistance:vsg_vShapeDistance
)

-------
-- 主生成函数（生成V字形线段）
-------
fn generateVShapes splineObj armLength acDistance spacing vShapeDistance:200.0 =
(
    if splineObj == undefined then
    (
        messageBox "请选择一条样条线！" title:"错误"
        return undefined
    )
    
    -- 创建V字形线段实例
    local vShapeObjects = instanceVShapeOnSpline splineObj armLength acDistance spacing vShapeDistance:vShapeDistance
    
    if vShapeObjects.count > 0 then
    (
        -- 创建一个组来管理所有V字形线段
        local groupName = "VShapes_" + (timestamp() as string)
        local vShapeGroup = group vShapeObjects name:groupName
        
        return vShapeGroup
    )
    else
    (
        return undefined
    )
)

-------
-- 基于双V字形点集创建片面模型
-- 参数：
--   dualVPoints: #(#(pointA1, pointB1, pointC1), #(pointA2, pointB2, pointC2)) 双V字形点集
--   objName: 对象名称
-- 返回：创建的mesh对象
-------
fn createDualVShapeSurface dualVPoints objName:"DualVShapeSurface" =
(
    try
    (
        if dualVPoints == undefined or dualVPoints.count != 2 then
        (
            messageBox "无效的双V字形点集！" title:"错误"
            return undefined
        )
        
        local vShape1 = dualVPoints[1]  -- 第一个V字形的三个点
        local vShape2 = dualVPoints[2]  -- 第二个V字形的三个点
        
        if vShape1.count != 3 or vShape2.count != 3 then
        (
            messageBox "V字形点集格式错误！" title:"错误"
            return undefined
        )
        
        -- 定义顶点数组（6个顶点：两个V字形各3个点）
        local verts = #()
        append verts vShape1[1]  -- A1
        append verts vShape1[2]  -- B1
        append verts vShape1[3]  -- C1
        append verts vShape2[1]  -- A2
        append verts vShape2[2]  -- B2
        append verts vShape2[3]  -- C2
        
        -- 定义面片（连接两个V字形形成表面）
        local faces = #()
        
        -- 连接A1-B1-A2形成三角形
        append faces [1, 2, 4]  -- A1, B1, A2
        
        -- 连接B1-B2-A2形成三角形
        append faces [2, 5, 4]  -- B1, B2, A2
        
        -- 连接B1-C1-B2形成三角形
        append faces [2, 3, 5]  -- B1, C1, B2
        
        -- 连接C1-C2-B2形成三角形
        append faces [3, 6, 5]  -- C1, C2, B2
        
        -- 创建mesh对象
        local surfaceMesh = mesh vertices:verts faces:faces
        surfaceMesh.name = objName
        
        -- 设置材质ID
        for i = 1 to surfaceMesh.numfaces do
        (
            setFaceMatID surfaceMesh i 1
        )
        
        -- 更新mesh
        update surfaceMesh
        
        return surfaceMesh
    )
    catch
    (
        return undefined
    )
)

-------
-- 生成片面模型函数
-------
fn generateSplineSurface splineObj width subdivisions =
(
    if splineObj == undefined then
    (
        messageBox "请选择一条样条线！" title:"错误"
        return undefined
    )
    
    -- 创建片面模型
    local surfaceObj = convertSplineToSurface splineObj width subdivisions objName:("SplineSurface_" + (timestamp() as string))
    
    if surfaceObj != undefined then
    (
        return surfaceObj
    )
    else
    (
        return undefined
    )
)

-------
-- 基于双V字形参数生成片面模型函数
-- 参数：
--   centerPos: 中心位置
--   direction: 前进方向向量
--   armLength: 臂长
--   acDistance: A、C两点间距离
--   vShapeDistance: 两个V字形之间的距离
-- 返回：创建的mesh对象
-------
fn generateDualVShapeSurface centerPos direction armLength acDistance vShapeDistance =
(
    try
    (
        -- 计算双V字形点集
        local dualVPoints = calculateDualVShapePoints centerPos direction armLength acDistance vShapeDistance
        
        if dualVPoints != undefined then
        (
            -- 创建片面模型
            local surfaceObj = createDualVShapeSurface dualVPoints objName:("DualVShapeSurface_" + (timestamp() as string))
            return surfaceObj
        )
        else
        (
            return undefined
        )
    )
    catch
    (
        return undefined
    )
)

-------
-- 用户界面
-------
rollout VShapeGeneratorRol "V字形线段生成器 v1.4.0" width:220 height:530
(
    groupBox 'grp1' "样条线选择" pos:[8,8] width:204 height:60 align:#left
    button 'btnSelectSpline' "选择样条线" pos:[15,25] width:80 height:25 align:#left
    label 'lblSplineCount' "已选择: 0 条" pos:[105,32] width:100 height:15 align:#left
    
    groupBox 'grp2' "V字形参数" pos:[8,75] width:204 height:140 align:#left
    label 'lblArmLength' "臂长 (A-B距离):" pos:[15,95] width:90 height:15 align:#left
    spinner 'spnArmLength' "" pos:[110,95] width:90 height:16 range:[50,2000,300] type:#float align:#left
    
    label 'lblAcDistance' "A-C距离:" pos:[15,120] width:70 height:15 align:#left
    spinner 'spnAcDistance' "" pos:[110,120] width:90 height:16 range:[50,600,200] type:#float align:#left
    
    label 'lblSpacing' "实例间距:" pos:[15,145] width:70 height:15 align:#left
    spinner 'spnSpacing' "" pos:[110,145] width:90 height:16 range:[50,2000,500] type:#float align:#left
    
    label 'lblVShapeDistance' "上下间距:" pos:[15,170] width:70 height:15 align:#left
    spinner 'spnVShapeDistance' "" pos:[110,170] width:90 height:16 range:[50,1000,200] type:#float align:#left
    
    checkbox 'chkPreview' "显示预览" pos:[15,195] width:80 height:20 align:#left
    
    groupBox 'grp3' "片面生成" pos:[8,225] width:204 height:115 align:#left
    label 'lblSurfaceWidth' "片面宽度:" pos:[15,245] width:70 height:15 align:#left
    spinner 'spnSurfaceWidth' "" pos:[110,245] width:90 height:16 range:[10,500,100] type:#float align:#left
    
    label 'lblSubdivisions' "细分数:" pos:[15,270] width:70 height:15 align:#left
    spinner 'spnSubdivisions' "" pos:[110,270] width:90 height:16 range:[5,100,20] type:#integer align:#left
    
    button 'btnGenerateSurface' "生成样条线片面" pos:[15,290] width:90 height:20 align:#left
    button 'btnGenerateDualVSurface' "生成双V片面" pos:[115,290] width:85 height:20 align:#left
    button 'btnGenerateVShapeSurface' "生成单点双V片面" pos:[50,315] width:120 height:20 align:#left
    
    groupBox 'grp4' "V字形操作" pos:[8,350] width:204 height:40 align:#left
    button 'btnGenerate' "生成V字形线段" pos:[50,365] width:120 height:20 align:#left
    
    groupBox 'grp5' "使用说明" pos:[8,400] width:204 height:125 align:#left
    label 'lblHelp1' "1. 选择一条或多条样条线" pos:[15,420] width:180 height:15 align:#left
    label 'lblHelp2' "2. 调整V字形参数:" pos:[15,440] width:120 height:15 align:#left
    label 'lblHelp3' "   - 臂长: A到B点距离" pos:[15,455] width:150 height:15 align:#left
    label 'lblHelp4' "   - A-C距离: 底边宽度" pos:[15,470] width:150 height:15 align:#left
    label 'lblHelp5' "   - 实例间距: V字形间隔" pos:[15,485] width:150 height:15 align:#left
    label 'lblHelp6' "   - 上下间距: 双V垂直距离" pos:[15,500] width:150 height:15 align:#left
    label 'lblHelp7' "3. 启用预览查看效果" pos:[15,515] width:150 height:15 align:#left
    
    -- 预览更新函数
    fn updateVShapePreview =
    (
        if chkPreview.checked and vsg_selectedSpline != undefined then
        (
            -- 更新全局参数
            vsg_armLength = spnArmLength.value
            vsg_acDistance = spnAcDistance.value
            vsg_instanceSpacing = spnSpacing.value
            vsg_vShapeDistance = spnVShapeDistance.value
            
            -- 触发视口重绘（gw绘制会在回调中自动执行）
            redrawViews()
            
            -- 刷新视图
            redrawviews()
        )
    )
    
    -- 界面事件
    on VShapeGeneratorRol open do
    (
        unregisterVShapePreview()
        vsg_previewEnabled = false
        chkPreview.checked = false
        vsg_selectedSpline = undefined
        lblSplineCount.text = "已选择: 0 条"
        
        -- 初始化界面参数
        spnArmLength.value = vsg_armLength
        spnAcDistance.value = vsg_acDistance
        spnSpacing.value = vsg_instanceSpacing
        spnVShapeDistance.value = vsg_vShapeDistance
        spnSurfaceWidth.value = vsg_surfaceWidth
        spnSubdivisions.value = vsg_subdivisions
    )
    
    on VShapeGeneratorRol close do
    (
        unregisterVShapePreview()
        vsg_selectedSpline = undefined
        vsg_previewEnabled = false
    )
    
    on btnSelectSpline pressed do
    (
        local selectedShapes = #()
        for obj in selection do
        (
            if superclassof obj == Shape then
                append selectedShapes obj
        )
        
        if selectedShapes.count >= 1 then
        (
            vsg_selectedSpline = selectedShapes[1]
            lblSplineCount.text = "已选择: 1 条"
            if selectedShapes.count > 1 then
                messageBox ("检测到" + selectedShapes.count as string + "条样条线，将使用第一条。") title:"提示"
        )
        else
        (
            vsg_selectedSpline = undefined
            lblSplineCount.text = "已选择: 0 条"
            messageBox "请选择一条样条线！" title:"提示"
        )
        
        updateVShapePreview()
    )
    
    on chkPreview changed state do
    (
        vsg_previewEnabled = state
        if state then
        (
            if vsg_selectedSpline != undefined then
            (
                registerVShapePreview()
                updateVShapePreview()
            )
            else
            (
                messageBox "请先选择一条样条线！" title:"提示"
                chkPreview.checked = false
                vsg_previewEnabled = false
            )
        )
        else
        (
            unregisterVShapePreview()
        )
    )
    
    on spnArmLength changed val do updateVShapePreview()
    on spnAcDistance changed val do updateVShapePreview()
    on spnSpacing changed val do updateVShapePreview()
    on spnVShapeDistance changed val do updateVShapePreview()
    
    on spnSurfaceWidth changed val do
    (
        vsg_surfaceWidth = val
    )
    
    on spnSubdivisions changed val do
    (
        vsg_subdivisions = val
    )
    
    on btnGenerate pressed do
    (
        if vsg_selectedSpline == undefined then
        (
            messageBox "请先选择一条样条线！" title:"错误"
            return()
        )
        
        undo on
        (
            -- 关闭预览
            if chkPreview.checked then
            (
                chkPreview.checked = false
                vsg_previewEnabled = false
                unregisterVShapePreview()
            )
            
            -- 收集参数
            local armLength = spnArmLength.value
            local acDistance = spnAcDistance.value
            local spacing = spnSpacing.value
            local vShapeDistance = spnVShapeDistance.value
            
            -- 更新全局参数
            vsg_armLength = armLength
            vsg_acDistance = acDistance
            vsg_instanceSpacing = spacing
            vsg_vShapeDistance = vShapeDistance
            
            -- 生成V字形线段
            local result = generateVShapes vsg_selectedSpline armLength acDistance spacing vShapeDistance:vShapeDistance
            
            if result != undefined then
            (
                select result
                messageBox ("成功生成V字形线段！\n对象名称: " + result.name + "\n包含 " + result.children.count as string + " 个线段实例") title:"完成"
            )
            else
            (
                messageBox "生成失败！" title:"错误"
            )
        )
    )
    
    on btnGenerateSurface pressed do
    (
        if vsg_selectedSpline == undefined then
        (
            messageBox "请先选择一条样条线！" title:"错误"
            return()
        )
        
        undo on
        (
            -- 关闭预览
            if chkPreview.checked then
            (
                chkPreview.checked = false
                vsg_previewEnabled = false
                unregisterVShapePreview()
            )
            
            -- 收集参数
            local surfaceWidth = spnSurfaceWidth.value
            local subdivisions = spnSubdivisions.value
            
            -- 更新全局参数
            vsg_surfaceWidth = surfaceWidth
            vsg_subdivisions = subdivisions
            
            -- 生成片面模型
            local result = generateSplineSurface vsg_selectedSpline surfaceWidth subdivisions
            
            if result != undefined then
            (
                select result
                messageBox ("成功生成片面模型！\n对象名称: " + result.name + "\n顶点数: " + result.numverts as string + "\n面数: " + result.numfaces as string) title:"完成"
            )
            else
            (
                messageBox "生成失败，请检查参数设置！" title:"错误"
            )
        )
    )
    
    on btnGenerateDualVSurface pressed do
    (
        if vsg_selectedSpline == undefined then
        (
            messageBox "请先选择一条样条线！" title:"错误"
            return()
        )
        
        undo on
        (
            -- 关闭预览
            if chkPreview.checked then
            (
                chkPreview.checked = false
                vsg_previewEnabled = false
                unregisterVShapePreview()
            )
            
            -- 收集参数
            local armLength = spnArmLength.value
            local acDistance = spnAcDistance.value
            local spacing = spnSpacing.value
            local vShapeDistance = spnVShapeDistance.value
            
            -- 更新全局参数
            vsg_armLength = armLength
            vsg_acDistance = acDistance
            vsg_instanceSpacing = spacing
            vsg_vShapeDistance = vShapeDistance
            
            -- 沿样条线生成多个双V字形片面
            local surfaceObjects = #()
            local splineLength = curveLength vsg_selectedSpline
            local numInstances = (splineLength / spacing) as integer
            
            if numInstances > 0 then
            (
                for i = 0 to numInstances do
                (
                    local param = i as float / numInstances as float
                    if param > 1.0 then param = 1.0
                    
                    -- 获取样条线上的位置和方向
                    local currentPos = lengthInterp vsg_selectedSpline 1 param
                    local tangentDir = normalize (lengthTangent vsg_selectedSpline 1 param)
                    
                    -- 生成双V字形片面
                    local surfaceObj = generateDualVShapeSurface currentPos tangentDir armLength acDistance vShapeDistance
                    
                    if surfaceObj != undefined then
                    (
                        append surfaceObjects surfaceObj
                    )
                )
                
                if surfaceObjects.count > 0 then
                (
                    select surfaceObjects
                    messageBox ("成功生成双V字形片面！\n生成了 " + surfaceObjects.count as string + " 个片面对象") title:"完成"
                )
                else
                (
                    messageBox "生成失败！" title:"错误"
                )
            )
            else
            (
                messageBox "样条线长度不足或间距过大！" title:"错误"
            )
        )
    )
    
    on btnGenerateVShapeSurface pressed do
    (
        undo on
        (
            -- 收集参数
            local armLength = spnArmLength.value
            local acDistance = spnAcDistance.value
            local vShapeDistance = spnVShapeDistance.value
            
            -- 在世界原点生成单个双V字形片面
            local centerPos = [0, 0, 0]
            local direction = [1, 0, 0]  -- X轴正方向
            
            local surfaceObj = generateDualVShapeSurface centerPos direction armLength acDistance vShapeDistance
            
            if surfaceObj != undefined then
            (
                select surfaceObj
                messageBox ("成功生成单点双V字形片面！\n对象名称: " + surfaceObj.name + "\n顶点数: " + surfaceObj.numverts as string + "\n面数: " + surfaceObj.numfaces as string) title:"完成"
            )
            else
            (
                messageBox "生成失败！" title:"错误"
            )
        )
    )
)

-- Function definition verification (silent)
try
(
    -- Verify functions are defined without printing
    local functionsOK = (createVShapeGeometry != undefined and 
                        calculateVShapePoints != undefined and
                        instanceVShapeOnSpline != undefined and
                        convertSplineToSurface != undefined and
                        generateSplineSurface != undefined)
)
catch
(
    -- Silent error handling
)

CreateDialog VShapeGeneratorRol