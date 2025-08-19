-------
-- DashedShape v2.0.0 - 重构版本
-- 核心改进：预览和生成使用统一的算法逻辑，确保完全一致
-------

-- 全局变量
global ds_previewColor = color 0 255 0  -- 绿色预览线条
global ds_selectedObjs = #()
global ds_previewEnabled = false
global ds_solidLength = 600
global ds_gapLength = 900
global ds_lineWidth = 40
global ds_lineThickness = 0
global ds_useLinear = false

-------
-- 核心算法：统一的虚线分割逻辑
-- 这个函数负责计算虚线段的位置，预览和生成都使用这个函数
-------
fn calculateDashedSegments splineObj splineIdx solidLen gapLen =
(
    local result = #()
    local splineLength = curveLength splineObj splineIdx
    
    if solidLen > 0 and splineLength > 0 then
    (
        if gapLen <= 0.001 then
        (
            -- 特殊情况：间隔为0，生成连续实线
            -- 按solidLen分割，连续排列
            local numSegments = (splineLength / solidLen) as integer
            local remainder = splineLength - (numSegments * solidLen)
            
            -- 生成完整的实线段
            for segIdx = 1 to numSegments do
            (
                local segStartDist = (segIdx - 1) * solidLen
                local segEndDist = segStartDist + solidLen
                
                local startParam = segStartDist / splineLength
                local endParam = segEndDist / splineLength
                
                local startPos = lengthInterp splineObj splineIdx startParam
                local endPos = lengthInterp splineObj splineIdx endParam
                
                append result #(startPos, endPos)
            )
            
            -- 处理剩余部分（如果有的话）
            if remainder > 0.001 then
            (
                local lastStartDist = numSegments * solidLen
                local lastStartParam = lastStartDist / splineLength
                local lastEndParam = 1.0  -- 到样条线末尾
                
                local startPos = lengthInterp splineObj splineIdx lastStartParam
                local endPos = lengthInterp splineObj splineIdx lastEndParam
                
                append result #(startPos, endPos)
            )
        )
        else
        (
            -- 正常情况：有间隔的虚线
            local segmentCycle = solidLen + gapLen  -- 一个完整周期的长度
            local currentDist = 0.0
            
            while currentDist < splineLength do
            (
                -- 计算当前实线段的起始和结束距离
                local segStartDist = currentDist
                local segEndDist = currentDist + solidLen
                
                -- 确保不超出样条线长度
                if segStartDist >= splineLength then break
                if segEndDist > splineLength then segEndDist = splineLength
                
                -- 转换为参数
                local startParam = segStartDist / splineLength
                local endParam = segEndDist / splineLength
                
                -- 计算3D位置
                local startPos = lengthInterp splineObj splineIdx startParam
                local endPos = lengthInterp splineObj splineIdx endParam
                
                append result #(startPos, endPos)
                
                -- 移动到下一个周期的起始位置
                currentDist += segmentCycle
            )
        )
    )
    
    return result
)

-------
-- 预览绘制函数
-------
fn drawDashedPreview objs solidLen gapLen lineWidth lineThickness generatePlane =
(
    if objs.count > 0 then
    (
        gw.setTransform(matrix3 1)
        gw.setColor #line ds_previewColor
        
        for obj in objs do
        (
            if obj != undefined and isValidNode obj and superclassof obj == Shape then
            (
                for splineIdx = 1 to numSplines obj do
                (
                    -- 使用统一的核心算法计算线段位置
                    local segments = calculateDashedSegments obj splineIdx solidLen gapLen
                    local halfWidth = if lineWidth > 0 then lineWidth / 2.0 else 0.5
                    
                    -- 绘制每个线段
                    for segment in segments do
                    (
                        local startPos = segment[1]
                        local endPos = segment[2]
                        
                        if generatePlane then
                        (
                            -- 绘制平面预览
                            local segmentDir = normalize (endPos - startPos)
                            local perpDir = normalize (cross segmentDir [0,0,1])
                            
                            local v1 = startPos - perpDir * halfWidth
                            local v2 = startPos + perpDir * halfWidth
                            local v3 = endPos + perpDir * halfWidth
                            local v4 = endPos - perpDir * halfWidth
                            
                            gw.polyline #(v1, v2, v3, v4, v1) false
                        )
                        else
                        (
                            -- 绘制线条预览
                            if lineWidth > 0 or lineThickness > 0 then
                            (
                                local lineDir = normalize (endPos - startPos)
                                local perpDir = normalize (cross lineDir [0,0,1])
                                local upDir = [0,0,1]
                                
                                local halfThickness = if lineThickness > 0 then lineThickness / 2.0 else 0.0
                                
                                -- 绘制底面
                                local p1_bottom = startPos + perpDir * halfWidth - upDir * halfThickness
                                local p2_bottom = startPos - perpDir * halfWidth - upDir * halfThickness
                                local p3_bottom = endPos - perpDir * halfWidth - upDir * halfThickness
                                local p4_bottom = endPos + perpDir * halfWidth - upDir * halfThickness
                                
                                gw.polyline #(p1_bottom, p2_bottom, p3_bottom, p4_bottom, p1_bottom) false
                                
                                -- 如果有厚度，绘制立体效果
                                if lineThickness > 0 then
                                (
                                    local p1_top = startPos + perpDir * halfWidth + upDir * halfThickness
                                    local p2_top = startPos - perpDir * halfWidth + upDir * halfThickness
                                    local p3_top = endPos - perpDir * halfWidth + upDir * halfThickness
                                    local p4_top = endPos + perpDir * halfWidth + upDir * halfThickness
                                    
                                    gw.polyline #(p1_top, p2_top, p3_top, p4_top, p1_top) false
                                    gw.polyline #(p1_bottom, p1_top) false
                                    gw.polyline #(p2_bottom, p2_top) false
                                    gw.polyline #(p3_bottom, p3_top) false
                                    gw.polyline #(p4_bottom, p4_top) false
                                )
                            )
                            else
                            (
                                -- 简单线条
                                gw.polyline #(startPos, endPos) false
                            )
                        )
                    )
                )
            )
        )
        
        gw.enlargeUpdateRect #whole
        gw.updateScreen()
    )
)

-------
-- 生成函数：创建实际的几何体
-------
fn generateDashedShape sourceObj solidLen gapLen lineWidth lineThickness generatePlane useLinear =
(
    local newObj = copy sourceObj
    convertToSplineShape newObj
    
    -- 创建新的样条线形状来存储结果
    local resultShape = SplineShape()
    resultShape.name = sourceObj.name + "_Dashed"
    
    for splineIdx = 1 to numSplines newObj do
    (
        -- 使用与预览完全相同的核心算法
        local segments = calculateDashedSegments newObj splineIdx solidLen gapLen
        
        -- 为每个线段创建样条线
        for segment in segments do
        (
            local startPos = segment[1]
            local endPos = segment[2]
            
            addNewSpline resultShape
            local currentSplineIdx = numSplines resultShape
            addKnot resultShape currentSplineIdx #corner #line startPos
            addKnot resultShape currentSplineIdx #corner #line endPos
        )
    )
    
    updateShape resultShape
    
    -- 清理临时对象
    delete newObj
    
    -- 应用材质和渲染设置
    if generatePlane then
    (
        -- 生成平面几何体
        local planeObj = createPlaneFromSpline resultShape lineWidth
        if planeObj != undefined then
        (
            delete resultShape  -- 清理临时样条线对象
            return planeObj
        )
    )
    else if lineWidth > 0 or lineThickness > 0 then
    (
        -- 设置渲染属性
        resultShape.render_renderable = true
        resultShape.render_displayRenderMesh = true
        resultShape.render_rectangular = true
        resultShape.render_viewport_rectangular = true
        resultShape.render_width = lineWidth
        resultShape.render_length = lineThickness
    )
    
    return resultShape
)

-------
-- 创建平面几何体的辅助函数
-------
fn createPlaneFromSpline splineShape planeWidth =
(
    try
    (
        local verts = #()
        local faces = #()
        local vertIndex = 1
        
        for splineIdx = 1 to numSplines splineShape do
        (
            local segCount = numSegments splineShape splineIdx
            local halfWidth = planeWidth / 2.0
            
            for segIdx = 1 to segCount do
            (
                local startParam = (segIdx - 1) as float / segCount as float
                local endParam = segIdx as float / segCount as float
                
                local startPos = lengthInterp splineShape splineIdx startParam
                local endPos = lengthInterp splineShape splineIdx endParam
                
                local segmentDir = normalize (endPos - startPos)
                local perpDir = normalize (cross segmentDir [0,0,1])
                
                local v1 = startPos - perpDir * halfWidth
                local v2 = startPos + perpDir * halfWidth
                local v3 = endPos + perpDir * halfWidth
                local v4 = endPos - perpDir * halfWidth
                
                append verts v1
                append verts v2
                append verts v3
                append verts v4
                
                local face1 = [vertIndex, vertIndex+1, vertIndex+2]
                local face2 = [vertIndex, vertIndex+2, vertIndex+3]
                
                append faces face1
                append faces face2
                
                vertIndex += 4
            )
        )
        
        if verts.count > 0 and faces.count > 0 then
        (
            local meshObj = mesh vertices:verts faces:faces
            meshObj.name = splineShape.name + "_Plane"
            return meshObj
        )
    )
    catch
    (
        return undefined
    )
    
    return undefined
)

-------
-- 预览系统
-------
fn initDashedPreview =
(
    try
    (
        if ds_previewEnabled and ds_selectedObjs.count > 0 then
        (
            drawDashedPreview ds_selectedObjs ds_solidLength ds_gapLength ds_lineWidth ds_lineThickness (chkPlane != undefined and chkPlane.checked)
        )
    )
    catch()
)

fn registerPreview =
(
    unregisterRedrawViewsCallback initDashedPreview
    registerRedrawViewsCallback initDashedPreview
    redrawviews()
)

fn unregisterPreview =
(
    unregisterRedrawViewsCallback initDashedPreview
    forcecompleteredraw()
)

-------
-- 用户界面
-------
try destroyDialog DashedShapeRol catch()
rollout DashedShapeRol "DashedShape v2.0.0" width:205 height:320
(
    groupBox 'grp1' "参数" pos:[8,8] width:189 height:170 align:#left
    spinner 'spn1' "虚线：" pos:[17,25] width:135 height:20 range:[0,10000,600] type:#worldunits scale:0.01
    spinner 'spn2' "间隔：" pos:[17,50] width:135 height:20 range:[0,10000,900] type:#worldunits scale:0.01
    spinner 'spn3' "宽度：" pos:[17,75] width:135 height:20 range:[0,10000,40] type:#worldunits scale:0.01
    spinner 'spn4' "厚度：" pos:[17,100] width:135 height:20 range:[0,10000,0] type:#worldunits scale:0.01
    checkbox 'onLinear' "线性" pos:[22,125] width:80 height:22 align:#left
    checkbox 'chkPlane' "生成平面" pos:[110,125] width:80 height:22 align:#left
    checkbox 'chkPreview' "显示预览" pos:[22,150] width:80 height:22 align:#left
    
    button genBtn "生成" pos:[44,185] width:120 height:40
    
    -- 更新预览
    fn updatePreview =
    (
        if chkPreview.checked then
        (
            ds_selectedObjs = selection as array
            ds_solidLength = spn1.value
            ds_gapLength = spn2.value
            ds_lineWidth = spn3.value
            ds_lineThickness = spn4.value
            ds_useLinear = onLinear.checked
            redrawviews()
        )
    )
    
    -- 界面事件
    on DashedShapeRol open do
    (
        unregisterPreview()
        ds_previewEnabled = false
        chkPreview.checked = false
        chkPlane.checked = false
        spn4.enabled = true
        
        ds_solidLength = spn1.value
        ds_gapLength = spn2.value
        ds_lineWidth = spn3.value
        ds_lineThickness = spn4.value
        ds_useLinear = onLinear.checked
    )
    
    on DashedShapeRol close do
    (
        unregisterPreview()
        ds_selectedObjs = #()
        ds_previewEnabled = false
    )
    
    on chkPreview changed state do
    (
        ds_previewEnabled = state
        if state then
        (
            if selection.count > 0 then
            (
                registerPreview()
                updatePreview()
            )
        )
        else
        (
            unregisterPreview()
        )
    )
    
    on spn1 changed val do updatePreview()
    on spn2 changed val do updatePreview()
    on spn3 changed val do updatePreview()
    on spn4 changed val do updatePreview()
    on onLinear changed state do updatePreview()
    
    on chkPlane changed state do
    (
        spn4.enabled = not state
        updatePreview()
    )
    
    on genBtn pressed do
    (
        undo on
        (
            local sourceSplArray = selection as array
            local notShapeArray = #()
            local ShapeArray = #()
            
            -- 检查选择对象
            for i in selection do
            (
                if superclassof i == Shape then 
                    append ShapeArray i 
                else 
                    append notShapeArray i
            )
            
            if notShapeArray.count == 0 and ShapeArray.count > 0 then
            (
                local resultObjects = #()
                
                for shapeObj in ShapeArray do
                (
                    -- 使用统一的生成算法
                    local newObj = generateDashedShape shapeObj spn1.value spn2.value spn3.value spn4.value chkPlane.checked onLinear.checked
                    if newObj != undefined then
                        append resultObjects newObj
                )
                
                -- 删除原始对象（静默处理）
                delete ShapeArray
                
                -- 选择生成的结果对象
                if resultObjects.count > 0 then
                    select resultObjects
            )
            else if ShapeArray.count == 0 then
            (
                messageBox ("请选择样条线对象！") title:"提示" beep:false
            )
        )
    )
)

CreateDialog DashedShapeRol