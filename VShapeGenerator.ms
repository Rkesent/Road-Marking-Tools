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
global vsg_lineThickness = 50.0   -- 线条厚度 (mm)
global vsg_vshapeHeight = 10.0     -- V字形片面高度 (mm)
global vsg_surfaceWidth = 100.0   -- 片面宽度 (mm)
global vsg_subdivisions = 20      -- 片面细分数
global vsg_previewObjects = #()   -- 预览对象数组

-------
-- 计算V字形的三个关键点（A、B、C）
-- 参数：
--   centerPos: B点位置（顶点中心）
--   direction: 前进方向向量
--   armLength: 臂长（A、C到B的距离）
--   acDistance: A、C两点间的距离
-- 返回：#(pointA, pointB, pointC)
-------
fn calculateVShapePoints centerPos direction armLength acDistance =
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
-- 创建V字形几何体（片面模型）
-- 参数：
--   points: #(pointA, pointB, pointC) 三个顶点
--   thickness: 线条厚度
--   height: 片面高度（Z轴方向）
--   objName: 对象名称
-- 返回：创建的mesh对象
-------
fn createVShapeGeometry points thickness height objName:"VShape" =
(
    try
    (
        local pointA = points[1]
        local pointB = points[2] 
        local pointC = points[3]
        
        local halfThickness = thickness / 2.0
        local halfHeight = height / 2.0
        local verts = #()
        local faces = #()
        
        -- 计算左臂（B到A）的垂直方向
        local leftArmDir = normalize (pointA - pointB)
        local leftPerpDir = normalize (cross leftArmDir [0,0,1])
        
        -- 计算右臂（B到C）的垂直方向
        local rightArmDir = normalize (pointC - pointB)
        local rightPerpDir = normalize (cross rightArmDir [0,0,1])
        
        -- 左臂的顶点（底面和顶面各4个）
        -- 底面顶点
        append verts (pointB + leftPerpDir * halfThickness + [0,0,-halfHeight])    -- 1: 左臂内侧起点底
        append verts (pointB - leftPerpDir * halfThickness + [0,0,-halfHeight])    -- 2: 左臂外侧起点底
        append verts (pointA + leftPerpDir * halfThickness + [0,0,-halfHeight])    -- 3: 左臂内侧终点底
        append verts (pointA - leftPerpDir * halfThickness + [0,0,-halfHeight])    -- 4: 左臂外侧终点底
        
        -- 顶面顶点
        append verts (pointB + leftPerpDir * halfThickness + [0,0,halfHeight])     -- 5: 左臂内侧起点顶
        append verts (pointB - leftPerpDir * halfThickness + [0,0,halfHeight])     -- 6: 左臂外侧起点顶
        append verts (pointA + leftPerpDir * halfThickness + [0,0,halfHeight])     -- 7: 左臂内侧终点顶
        append verts (pointA - leftPerpDir * halfThickness + [0,0,halfHeight])     -- 8: 左臂外侧终点顶
        
        -- 右臂的顶点（底面和顶面各4个）
        -- 底面顶点
        append verts (pointB - rightPerpDir * halfThickness + [0,0,-halfHeight])   -- 9: 右臂内侧起点底
        append verts (pointB + rightPerpDir * halfThickness + [0,0,-halfHeight])   -- 10: 右臂外侧起点底
        append verts (pointC - rightPerpDir * halfThickness + [0,0,-halfHeight])   -- 11: 右臂内侧终点底
        append verts (pointC + rightPerpDir * halfThickness + [0,0,-halfHeight])   -- 12: 右臂外侧终点底
        
        -- 顶面顶点
        append verts (pointB - rightPerpDir * halfThickness + [0,0,halfHeight])    -- 13: 右臂内侧起点顶
        append verts (pointB + rightPerpDir * halfThickness + [0,0,halfHeight])    -- 14: 右臂外侧起点顶
        append verts (pointC - rightPerpDir * halfThickness + [0,0,halfHeight])    -- 15: 右臂内侧终点顶
        append verts (pointC + rightPerpDir * halfThickness + [0,0,halfHeight])    -- 16: 右臂外侧终点顶
        
        -- 创建面
        -- 左臂底面
        append faces [1, 3, 2]  -- 左臂底面三角形1
        append faces [2, 3, 4]  -- 左臂底面三角形2
        
        -- 左臂顶面
        append faces [5, 6, 7]  -- 左臂顶面三角形1
        append faces [6, 8, 7]  -- 左臂顶面三角形2
        
        -- 左臂侧面
        append faces [1, 2, 5]  -- 左臂内侧面1
        append faces [2, 6, 5]  -- 左臂内侧面2
        append faces [2, 4, 6]  -- 左臂外侧面1
        append faces [4, 8, 6]  -- 左臂外侧面2
        append faces [3, 7, 4]  -- 左臂端面1
        append faces [4, 7, 8]  -- 左臂端面2
        append faces [1, 5, 3]  -- 左臂端面3
        append faces [3, 5, 7]  -- 左臂端面4
        
        -- 右臂底面
        append faces [9, 10, 11]  -- 右臂底面三角形1
        append faces [10, 12, 11] -- 右臂底面三角形2
        
        -- 右臂顶面
        append faces [13, 15, 14] -- 右臂顶面三角形1
        append faces [14, 15, 16] -- 右臂顶面三角形2
        
        -- 右臂侧面
        append faces [9, 13, 10]  -- 右臂内侧面1
        append faces [10, 13, 14] -- 右臂内侧面2
        append faces [10, 14, 12] -- 右臂外侧面1
        append faces [12, 14, 16] -- 右臂外侧面2
        append faces [11, 12, 15] -- 右臂端面1
        append faces [12, 16, 15] -- 右臂端面2
        append faces [9, 11, 13]  -- 右臂端面3
        append faces [11, 15, 13] -- 右臂端面4
        
        -- 创建mesh对象
        local vShapeMesh = mesh vertices:verts faces:faces
        vShapeMesh.name = objName
        
        -- 设置材质ID
        for i = 1 to vShapeMesh.numfaces do
        (
            setFaceMatID vShapeMesh i 1
        )
        
        -- 更新mesh
        update vShapeMesh
        
        return vShapeMesh
    )
    catch
    (
        return undefined
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
            
            -- 获取样条线上的位置和切线方向
            local currentPos = lengthInterp splineObj 1 param
            local tangentDir = normalize (lengthTangent splineObj 1 param)
            
            -- 计算垂直方向（在XY平面内）
            local perpDir = normalize (cross tangentDir [0,0,1])
            
            -- 创建左右边界点
            local leftPoint = currentPos - perpDir * halfWidth
            local rightPoint = currentPos + perpDir * halfWidth
            
            append verts leftPoint
            append verts rightPoint
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
-- 在样条线上实例化V字形
-- 参数：
--   splineObj: 目标样条线对象
--   armLength: V字形臂长
--   acDistance: A、C两点间距离
--   spacing: 实例间距
--   thickness: 线条厚度
-- 返回：创建的V字形对象数组
-------
fn instanceVShapeOnSpline splineObj armLength acDistance spacing thickness height =
(
    local resultObjects = #()
    
    try
    (
        if splineObj == undefined or superclassof splineObj != Shape then
        (
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
        
        -- 沿样条线创建V字形实例
        for i = 1 to numInstances do
        (
            -- 计算当前位置参数（0.0 到 1.0）
            local param = (i - 1) * spacing / splineLength
            if param > 1.0 then param = 1.0
            
            -- 获取样条线上的位置和切线方向
            local currentPos = lengthInterp splineObj 1 param
            local tangentDir = lengthTangent splineObj 1 param
            
            -- 计算V字形的三个点
            local vPoints = calculateVShapePoints currentPos tangentDir armLength acDistance
            
            -- 创建V字形几何体
            local vShapeObj = createVShapeGeometry vPoints thickness height objName:("VShape_" + i as string)
            
            if vShapeObj != undefined then
            (
                append resultObjects vShapeObj
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
fn drawVShapePreviewInternal splineObj armLength acDistance spacing thickness height =
(
    -- 清空预览对象数组（不再需要存储对象）
    vsg_previewObjects = #()
    
    if splineObj == undefined or not vsg_previewEnabled then
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
        
        -- 绘制预览V字形线框
        for i = 1 to numInstances do
        (
            -- 计算当前位置参数
            local param = (i - 1) * spacing / splineLength
            if param > 1.0 then param = 1.0
            
            -- 获取样条线上的位置和方向
            local currentPos = lengthInterp splineObj 1 param
            local tangentDir = lengthTangent splineObj 1 param
            
            -- 计算V字形点
            local vPoints = calculateVShapePoints currentPos tangentDir armLength acDistance
            
            -- 计算V字形两条臂的垂直方向
            local leftArmDir = normalize (vPoints[1] - vPoints[2])
            local rightArmDir = normalize (vPoints[3] - vPoints[2])
            local leftPerp = normalize (cross leftArmDir [0,0,1])
            local rightPerp = normalize (cross rightArmDir [0,0,1])
            
            -- 计算厚度偏移
            local halfThickness = thickness / 2.0
            
            -- 使用gw绘制V字形轮廓
            if thickness > 0 then
            (
                -- 左臂矩形轮廓
                local leftP1 = vPoints[1] + leftPerp * halfThickness
                local leftP2 = vPoints[1] - leftPerp * halfThickness
                local leftP3 = vPoints[2] - leftPerp * halfThickness
                local leftP4 = vPoints[2] + leftPerp * halfThickness
                gw.polyline #(leftP1, leftP2, leftP3, leftP4, leftP1) false
                
                -- 右臂矩形轮廓
                local rightP1 = vPoints[2] + rightPerp * halfThickness
                local rightP2 = vPoints[2] - rightPerp * halfThickness
                local rightP3 = vPoints[3] - rightPerp * halfThickness
                local rightP4 = vPoints[3] + rightPerp * halfThickness
                gw.polyline #(rightP1, rightP2, rightP3, rightP4, rightP1) false
            )
            else
            (
                -- 简单的V字形线条
                gw.polyline #(vPoints[1], vPoints[2], vPoints[3]) false
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
        drawVShapePreviewInternal vsg_selectedSpline vsg_armLength vsg_acDistance vsg_instanceSpacing vsg_lineThickness vsg_vshapeHeight
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
-- 基于当前预览参数生成片面模型函数
-------
fn generateVShapesFromPreview thickness height =
(
    if not vsg_previewEnabled or vsg_selectedSpline == undefined then
    (
        messageBox "请先启用预览并选择样条线！" title:"错误"
        return undefined
    )
    
    -- 使用当前的全局参数生成V字形
    return generateVShapes vsg_selectedSpline vsg_armLength vsg_acDistance vsg_instanceSpacing thickness height
)

-------
-- 主生成函数（保留原有功能）
-------
fn generateVShapes splineObj armLength acDistance spacing thickness height =
(
    if splineObj == undefined then
    (
        messageBox "请选择一条样条线！" title:"错误"
        return undefined
    )
    
    -- 创建V字形实例
    local vShapeObjects = instanceVShapeOnSpline splineObj armLength acDistance spacing thickness height
    
    if vShapeObjects.count > 0 then
    (
        -- 创建一个组来管理所有V字形
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
-- 用户界面
-------
rollout VShapeGeneratorRol "V字形线段生成器 v1.1.0" width:220 height:580
(
    groupBox 'grp1' "样条线选择" pos:[8,8] width:204 height:60 align:#left
    button 'btnSelectSpline' "选择样条线" pos:[15,25] width:80 height:25 align:#left
    label 'lblSplineCount' "已选择: 0 条" pos:[105,32] width:100 height:15 align:#left
    
    groupBox 'grp2' "V字形参数" pos:[8,75] width:204 height:165 align:#left
    label 'lblArmLength' "臂长 (A-B距离):" pos:[15,95] width:90 height:15 align:#left
    spinner 'spnArmLength' "" pos:[110,95] width:90 height:16 range:[50,2000,300] type:#float align:#left
    
    label 'lblAcDistance' "A-C距离:" pos:[15,120] width:70 height:15 align:#left
    spinner 'spnAcDistance' "" pos:[110,120] width:90 height:16 range:[50,600,200] type:#float align:#left
    
    label 'lblSpacing' "实例间距:" pos:[15,145] width:70 height:15 align:#left
    spinner 'spnSpacing' "" pos:[110,145] width:90 height:16 range:[50,2000,500] type:#float align:#left
    
    label 'lblThickness' "线条厚度:" pos:[15,170] width:70 height:15 align:#left
    spinner 'spnThickness' "" pos:[110,170] width:90 height:16 range:[10,200,50] type:#float align:#left
    
    label 'lblVHeight' "片面高度:" pos:[15,195] width:70 height:15 align:#left
    spinner 'spnVHeight' "" pos:[110,195] width:90 height:16 range:[1,100,10] type:#float align:#left
    
    checkbox 'chkPreview' "显示预览" pos:[15,220] width:80 height:20 align:#left
    
    groupBox 'grp3' "片面生成" pos:[8,250] width:204 height:90 align:#left
    label 'lblSurfaceWidth' "片面宽度:" pos:[15,270] width:70 height:15 align:#left
    spinner 'spnSurfaceWidth' "" pos:[110,270] width:90 height:16 range:[10,500,100] type:#float align:#left
    
    label 'lblSubdivisions' "细分数:" pos:[15,295] width:70 height:15 align:#left
    spinner 'spnSubdivisions' "" pos:[110,295] width:90 height:16 range:[5,100,20] type:#integer align:#left
    
    button 'btnGenerateSurface' "生成片面模型" pos:[50,315] width:120 height:20 align:#left
    
    groupBox 'grp4' "V字形操作" pos:[8,350] width:204 height:40 align:#left
    button 'btnGenerate' "生成V字形" pos:[50,365] width:120 height:20 align:#left
    
    groupBox 'grp5' "使用说明" pos:[8,400] width:204 height:215 align:#left
    label 'lblHelp1' "1. 选择一条样条线作为路径" pos:[12,415] width:195 height:12 align:#left
    label 'lblHelp2' "2. 片面模型生成：" pos:[12,427] width:195 height:12 align:#left
    label 'lblHelp3' "   • 片面宽度：控制生成模型的宽度" pos:[12,439] width:195 height:12 align:#left
    label 'lblHelp4' "   • 细分数：控制模型的精细程度" pos:[12,451] width:195 height:12 align:#left
    label 'lblHelp5' "3. V字形参数：" pos:[12,463] width:195 height:12 align:#left
    label 'lblHelp6' "   • 臂长：控制A、C到B点的距离" pos:[12,475] width:195 height:12 align:#left
    label 'lblHelp7' "   • A-C距离：控制V字形的张开程度" pos:[12,487] width:195 height:12 align:#left
    label 'lblHelp8' "   • 实例间距：控制V字形之间的距离" pos:[12,499] width:195 height:12 align:#left
    label 'lblHelp9' "   • 线条厚度：控制V字形线条的粗细" pos:[12,511] width:195 height:12 align:#left
    label 'lblHelp10' "   • 片面高度：控制V字形片面的厚度" pos:[12,523] width:195 height:12 align:#left
    label 'lblHelp11' "4. 开启预览查看效果" pos:[12,535] width:195 height:12 align:#left
    label 'lblHelp12' "5. 选择生成片面模型或V字形线条" pos:[12,547] width:195 height:12 align:#left
    label 'lblHelp13' "注：片面模型将样条线转换为带宽度的面" pos:[12,559] width:195 height:12 align:#left
    label 'lblHelp14' "V字形生成多个实例并组合管理" pos:[12,571] width:195 height:12 align:#left
    label 'lblHelp15' "预览限制最多20个实例以提高性能" pos:[12,583] width:195 height:12 align:#left
    
    -- 预览更新函数
    fn updateVShapePreview =
    (
        if chkPreview.checked and vsg_selectedSpline != undefined then
        (
            -- 更新全局参数
            vsg_armLength = spnArmLength.value
            vsg_acDistance = spnAcDistance.value
            vsg_instanceSpacing = spnSpacing.value
            vsg_lineThickness = spnThickness.value
            vsg_vshapeHeight = spnVHeight.value
            
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
        spnThickness.value = vsg_lineThickness
        spnVHeight.value = vsg_vshapeHeight
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
    on spnThickness changed val do updateVShapePreview()
    on spnVHeight changed val do
    (
        vsg_vshapeHeight = val
        updateVShapePreview()
    )
    
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
            local thickness = spnThickness.value
            local height = spnVHeight.value
            
            -- 更新全局参数
            vsg_armLength = armLength
            vsg_acDistance = acDistance
            vsg_instanceSpacing = spacing
            vsg_lineThickness = thickness
            vsg_vshapeHeight = height
            
            -- 基于预览对象生成V字形片面模型
            local result = generateVShapesFromPreview thickness height
            
            if result != undefined then
            (
                select result
                messageBox ("成功生成V字形片面模型！\n对象名称: " + result.name + "\n包含 " + result.children.count as string + " 个片面实例\n基于当前预览参数生成") title:"完成"
            )
            else
            (
                messageBox "生成失败！请先启用预览并选择样条线。" title:"错误"
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