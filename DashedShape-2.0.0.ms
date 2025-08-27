-------
-- DashedShape v2.0.0 - 重构版本
-- 核心改进：预览和生成使用统一的算法逻辑，确保完全一致
-------

-- 全局变量
global ds_previewColor = color 0 255 0  -- 绿色预览线条
global ds_selectedObjs = #()
global ds_previewEnabled = false
global ds_solidLength = 600
global ds_gapLength = 900  -- 采样点之间的距离间隔
global ds_lineWidth = 40
global ds_lineThickness = 0
global ds_useLinear = false

-------
-- 核心算法：基于固定采样间隔的虚线分割逻辑
-- 这个函数负责计算虚线段的位置，预览和生成都使用这个函数
-- solidLen: 虚线长度（距离单位）
-- gapDist: 采样点之间的距离间隔（距离单位）
-------
fn calculateDashedSegments splineObj splineIdx solidLen gapDist =
(
    local result = #()
    local splineLength = curveLength splineObj splineIdx
    
    if solidLen > 0 and splineLength > 0 then
    (
        if gapDist <= 0.001 then
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
            -- 基于固定采样间隔的虚线生成
            -- 采样点按固定距离间隔分布，虚线段在这些采样点上生成
            local currentDist = 0.0
            
            while currentDist < splineLength do
            (
                -- 计算当前虚线段的起始和结束距离
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
                
                -- 移动到下一个采样点位置（固定间隔距离）
                currentDist += gapDist
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

-- 创建平面几何体的函数
fn createPlaneFromSpline sourceSpline planeWidth =
(
    try
    (
        local verts = #()
        local faces = #()
        local vertIndex = 1
        
        for splineIdx = 1 to numSplines sourceSpline do
        (
            local segCount = numSegments sourceSpline splineIdx
            local halfWidth = planeWidth / 2.0
            
            for segIdx = 1 to segCount do
            (
                local startParam = (segIdx - 1) as float / segCount as float
                local endParam = segIdx as float / segCount as float
                
                local startPos = lengthInterp sourceSpline splineIdx startParam
                local endPos = lengthInterp sourceSpline splineIdx endParam
                
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
            meshObj.name = sourceSpline.name + "_Plane"
            return meshObj
        )
    )
    catch
    (
        return undefined
    )
    
    return undefined
)

fn generateDashedShape sourceObj solidLen gapLen lineWidth lineThickness generatePlane useLinear =
(
    local newObj = copy sourceObj
    convertToSplineShape newObj
    
    -- 创建新的样条线形状来存储结果
    local resultShape = Line pos:[0,0,0] name:(sourceObj.name + "_Dashed")
    convertToSplineShape resultShape
    
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
rollout DashedShapeRol "DashedShape v2.0.0" width:205 height:350
(
    groupBox 'grp1' "参数" pos:[8,8] width:189 height:170 align:#left
    spinner 'spn1' "虚线长度：" pos:[17,25] width:135 height:20 range:[0,10000,300] type:#worldunits scale:0.01
    spinner 'spn2' "采样间隔：" pos:[17,50] width:135 height:20 range:[0,10000,500] type:#worldunits scale:0.01
    spinner 'spn3' "虚线宽度：" pos:[17,75] width:135 height:20 range:[0,10000,40] type:#worldunits scale:0.01
    spinner 'spn4' "虚线厚度：" pos:[17,100] width:135 height:20 range:[0,10000,0] type:#worldunits scale:0.01
    checkbox 'onLinear' "线性" pos:[10,125] width:40 height:22 align:#left
    checkbox 'chkPlane' "生成平面" pos:[80,125] width:70 height:22 align:#left
    checkbox 'chkPreview' "显示预览" pos:[10,150] width:70 height:22 align:#left
    checkbox 'chkQuadify' "四边形化" pos:[80,150] width:70 height:22 align:#left
    spinner 'spnQuadSize' "" pos:[150,155] width:30 height:22 range:[1,100,20] type:#integer
    
    groupBox 'grp2' "预设" pos:[8,185] width:189 height:100 align:#left
    button 'btnPreset1' "中短线" pos:[17,205] width:55 height:25 tooltip:"虚线长度:200\n采样间隔:600\n宽度:30"
    button 'btnPreset2' "斑马线" pos:[75,205] width:55 height:25 tooltip:"虚线长度:50\n采样间隔:101\n宽度:520"
    button 'btnPreset3' "高架桥69线" pos:[133,205] width:55 height:25 tooltip:"虚线长度:620\n采样间隔:1510\n宽度:30"
    button 'btnPreset4' "停车线" pos:[17,235] width:55 height:25 tooltip:"虚线长度:100\n采样间隔:200\n宽度:50"
    
    button genBtn "生成" pos:[44,295] width:120 height:40
    
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
        chkQuadify.checked = false
        spn4.enabled = true
        chkQuadify.enabled = false
        spnQuadSize.enabled = false
        
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
        chkQuadify.enabled = state
        spnQuadSize.enabled = (state and chkQuadify.checked)
        updatePreview()
    )
    
    on chkQuadify changed state do
    (
        spnQuadSize.enabled = (chkPlane.checked and state)
    )
    
    -- 预设按钮事件
    on btnPreset1 pressed do
     (
         -- 中短线：虚线长度：200 采样间隔：600，宽度：30
         spn1.value = 200
         spn2.value = 600
         spn3.value = 30
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 手动启用预览系统
         ds_previewEnabled = true
         if selection.count > 0 then
         (
             registerPreview()
             updatePreview()
         )
     )
    
    on btnPreset2 pressed do
     (
         -- 斑马线：虚线长度：50 采样间隔：101，宽度：520
         spn1.value = 50
         spn2.value = 101
         spn3.value = 520
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 手动启用预览系统
         ds_previewEnabled = true
         if selection.count > 0 then
         (
             registerPreview()
             updatePreview()
         )
     )
    
    on btnPreset3 pressed do
     (
         -- 高架桥69线：虚线长度：620 采样间隔：1510，宽度：30
         spn1.value = 620
         spn2.value = 1510
         spn3.value = 30
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 手动启用预览系统
         ds_previewEnabled = true
         if selection.count > 0 then
         (
             registerPreview()
             updatePreview()
         )
     )
    
    on btnPreset4 pressed do
     (
         -- 停车线：虚线长度：100 采样间隔：200，宽度：50
         spn1.value = 100
         spn2.value = 200
         spn3.value = 50
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 手动启用预览系统
         ds_previewEnabled = true
         if selection.count > 0 then
         (
             registerPreview()
             updatePreview()
         )
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
                    (
                        -- 如果勾选了四边形化，添加Quadify_Mesh修改器
                        if chkQuadify.checked and chkPlane.checked then
                        (
                            select newObj
                            modPanel.addModToSelection (Quadify_Mesh ()) ui:on
                            newObj.modifiers[#Quadify_Mesh].quadsize = spnQuadSize.value
                            -- 执行转换为多边形的宏命令
                            macros.run "Modifier Stack" "Convert_to_Poly"
                        )
                        append resultObjects newObj
                    )
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