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
global ds_mode = 1  -- 1=虚线模式, 2=实线模式
global ds_offsetDistance = 0  -- 偏移距离
global ds_translateOffset = false  -- 是否启用平移偏移

-------
-- 核心算法：虚线和实线的统一生成逻辑
-- 虚线模式：基于固定采样间隔的虚线分割逻辑
-- 实线模式：基于样条线本身结构的连续线段生成
-- solidLen: 虚线长度（距离单位）
-- gapDist: 采样点之间的距离间隔（距离单位，实线模式时为0）
-- useLinear: 是否使用线性模式
-- isRealSolid: 是否为真正的实线模式（区别于gapDist=0的连续虚线）
-------
fn calculateDashedSegments splineObj splineIdx solidLen gapDist useLinear isRealSolid offsetDist translateOffset =
(
    local result = #()
    local splineLength = curveLength splineObj splineIdx
    
    if splineLength > 0 then
    (
        if isRealSolid then
        (
            -- 实线模式：基于样条线本身结构生成连续线段
            if useLinear then
            (
                -- 线性模式：按样条线的节点数量分段
                local knotCount = numKnots splineObj splineIdx
                if knotCount >= 2 then
                (
                    for knotIdx = 1 to (knotCount - 1) do
                    (
                        local startParam = (knotIdx - 1) as float / (knotCount - 1) as float
                        local endParam = knotIdx as float / (knotCount - 1) as float
                        
                        local startPos = lengthInterp splineObj splineIdx startParam
                        local endPos = lengthInterp splineObj splineIdx endParam
                        
                        append result #(startPos, endPos)
                    )
                )
            )
            else
            (
                -- 弧度模式：根据样条线的曲率自适应采样
                local segCount = numSegments splineObj splineIdx
                if segCount > 0 then
                (
                    for segIdx = 1 to segCount do
                    (
                        local startParam = (segIdx - 1) as float / segCount as float
                        local endParam = segIdx as float / segCount as float
                        
                        local startPos = lengthInterp splineObj splineIdx startParam
                        local endPos = lengthInterp splineObj splineIdx endParam
                        
                        append result #(startPos, endPos)
                    )
                )
            )
        )
        else if gapDist <= 0.001 then
        (
            -- 连续虚线模式：按solidLen分割，连续排列
            if solidLen > 0 then
            (
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
        )
        else
        (
            -- 虚线模式：基于固定采样间隔的虚线生成
            if solidLen > 0 then
            (
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
    )
    
    -- 应用偏移处理
    if offsetDist != 0 and result.count > 0 then
    (
        for i = 1 to result.count do
        (
            local segment = result[i]
            local startPos = segment[1]
            local endPos = segment[2]
            
            -- 计算线段方向和垂直方向
            local segmentDir = normalize (endPos - startPos)
            local perpDir = normalize (cross segmentDir [0,0,1])
            
            if translateOffset then
             (
                 -- 平移偏移：线段沿垂直方向偏移
                 local offsetVector = perpDir * offsetDist
                 local newStartPos = startPos + offsetVector
                 local newEndPos = endPos + offsetVector
                 
                 result[i] = #(newStartPos, newEndPos)
             )
             else
             (
                 -- 旋转偏移：线段绕中心点旋转（默认模式）
                 local centerPos = (startPos + endPos) / 2.0
                 local segmentLength = distance startPos endPos
                 
                 -- 将偏移距离乘以100后作为旋转角度（度数）
                 local rotAngleRad = degToRad (offsetDist * 100.0)
                 
                 -- 计算线段的原始方向向量
                 local originalDir = normalize (endPos - startPos)
                 
                 -- 应用Z轴旋转：顺时针为正值，逆时针为负值
                 local cosAngle = cos rotAngleRad
                 local sinAngle = sin rotAngleRad
                 local rotatedDir = [originalDir.x * cosAngle - originalDir.y * sinAngle,
                                    originalDir.x * sinAngle + originalDir.y * cosAngle,
                                    originalDir.z]
                 
                 -- 计算旋转后的新端点位置
                 local halfSegment = rotatedDir * (segmentLength / 2.0)
                 local newStartPos = centerPos - halfSegment
                 local newEndPos = centerPos + halfSegment
                 
                 result[i] = #(newStartPos, newEndPos)
             )
        )
    )
    
    return result
)

-------
-- 预览绘制函数
-------
fn drawDashedPreview objs solidLen gapLen lineWidth lineThickness generatePlane useLinear isRealSolid =
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
                    local segments = calculateDashedSegments obj splineIdx solidLen gapLen useLinear isRealSolid ds_offsetDistance ds_translateOffset
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
    
    -- 判断是否为真正的实线模式
    local isRealSolid = (ds_mode == 2)
    
    -- 创建新的样条线形状来存储结果
    local resultShape = Line pos:[0,0,0] name:(sourceObj.name + (if isRealSolid then "_Solid" else "_Dashed"))
    convertToSplineShape resultShape
    
    for splineIdx = 1 to numSplines newObj do
    (
        -- 使用与预览完全相同的核心算法
        local segments = calculateDashedSegments newObj splineIdx solidLen gapLen useLinear isRealSolid ds_offsetDistance ds_translateOffset
        
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
            local isRealSolid = (ds_mode == 2)
            drawDashedPreview ds_selectedObjs ds_solidLength ds_gapLength ds_lineWidth ds_lineThickness (chkPlane != undefined and chkPlane.checked) ds_useLinear isRealSolid
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
rollout DashedShapeRol "DashedShape v2.0.0" width:205 height:470
(
    -- 模式选择
    groupBox 'grpMode' "模式" pos:[8,8] width:189 height:50 align:#left
    radiobuttons 'rdoMode' "" pos:[20,25] width:165 height:22 labels:#("虚线", "实线") default:1 columns:2 align:#left
    
    -- 参数设置
    groupBox 'grp1' "参数" pos:[8,65] width:189 height:220 align:#left
    spinner 'spn1' "虚线长度：" pos:[17,82] width:135 height:20 range:[0,10000,300] type:#worldunits scale:0.01
    spinner 'spn2' "采样间隔：" pos:[17,107] width:135 height:20 range:[0,10000,500] type:#worldunits scale:0.01
    spinner 'spn3' "线条宽度：" pos:[17,132] width:135 height:20 range:[0,10000,40] type:#worldunits scale:0.01
    spinner 'spn4' "线条厚度：" pos:[17,157] width:135 height:20 range:[0,10000,0] type:#worldunits scale:0.01
    spinner 'spnOffset' "旋转角度：" pos:[17,182] width:135 height:20 range:[-360,360,0] type:#float scale:1.0
    checkbox 'onLinear' "线性" pos:[10,207] width:40 height:22 align:#left
    checkbox 'chkPlane' "生成平面" pos:[80,207] width:70 height:22 align:#left
    checkbox 'chkRotateOffset' "平移偏移" pos:[10,232] width:70 height:22 align:#left
    checkbox 'chkPreview' "显示预览" pos:[80,232] width:70 height:22 align:#left
    checkbox 'chkQuadify' "四边形化" pos:[10,257] width:70 height:22 align:#left
    spinner 'spnQuadSize' "" pos:[80,262] width:30 height:22 range:[1,100,20] type:#integer
    
    groupBox 'grp2' "预设" pos:[8,292] width:189 height:130 align:#left
    button 'btnPreset1' "中短线" pos:[17,312] width:55 height:25 tooltip:"虚线长度:200\n采样间隔:600\n宽度:30"
    button 'btnPreset2' "斑马线" pos:[75,312] width:55 height:25 tooltip:"虚线长度:50\n采样间隔:101\n宽度:520"
    button 'btnPreset3' "高架桥69线" pos:[133,312] width:55 height:25 tooltip:"虚线长度:620\n采样间隔:1510\n宽度:30"
    button 'btnPreset4' "停车线" pos:[17,342] width:55 height:25 tooltip:"虚线长度:100\n采样间隔:200\n宽度:50"
    button 'btnPreset5' "路口引导线" pos:[75,342] width:55 height:25 tooltip:"虚线长度:100\n采样间隔:200\n宽度:25"
    button 'btnPreset6' "待转线" pos:[133,342] width:55 height:25 tooltip:"虚线长度:50\n采样间隔:90\n宽度:20"
    button 'btnPreset7' "实线" pos:[17,372] width:55 height:25 tooltip:"连续实线\n宽度:100"
    button 'btnPreset8' "双实线" pos:[75,372] width:55 height:25 tooltip:"双实线\n宽度:150"
    button 'btnPreset9' "边界线" pos:[133,372] width:55 height:25 tooltip:"边界线\n宽度:200"
    
    button genBtn "生成" pos:[44,432] width:120 height:40
    
    -- 更新预览
    fn updatePreview =
    (
        if chkPreview.checked then
        (
            ds_selectedObjs = selection as array
            ds_solidLength = spn1.value
            ds_gapLength = if ds_mode == 1 then spn2.value else 0  -- 实线模式时间隔为0
            ds_lineWidth = spn3.value
            ds_lineThickness = spn4.value
            ds_useLinear = onLinear.checked
            redrawviews()
        )
    )
    
    -- 更新UI界面状态
    fn updateUIState =
    (
        case rdoMode.state of
        (
            1: -- 虚线模式
            (
                spn1.caption = "虚线长度："
                spn1.enabled = true
                spn2.enabled = true
                spn3.caption = "线条宽度："
                ds_mode = 1
            )
            2: -- 实线模式
            (
                spn1.caption = "（无需设置）"
                spn1.enabled = false  -- 实线模式下不需要分段长度参数
                spn2.enabled = false  -- 实线模式下不需要采样间隔参数
                spn3.caption = "线条宽度："
                ds_mode = 2
            )
        )
        
        -- 根据偏移模式更新偏移参数的标签
        if chkRotateOffset.checked then
            spnOffset.caption = "偏移距离："
        else
            spnOffset.caption = "旋转角度："
        
        -- 同步偏移参数到全局变量
        ds_offsetDistance = spnOffset.value
        ds_translateOffset = chkRotateOffset.checked
        
        -- 调用更新预览（现在updatePreview已经定义了）
        updatePreview()
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
        
        -- 初始化为虚线模式
        rdoMode.state = 1
        ds_mode = 1
        
        ds_solidLength = spn1.value
        ds_gapLength = spn2.value
        ds_lineWidth = spn3.value
        ds_lineThickness = spn4.value
        ds_useLinear = onLinear.checked
        ds_offsetDistance = spnOffset.value
        ds_translateOffset = chkRotateOffset.checked
        
        -- 最后调用UI状态更新（此时所有控件都已初始化）
        updateUIState()
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
    
    on rdoMode changed state do updateUIState()
    on spn1 changed val do updatePreview()
    on spn2 changed val do updatePreview()
    on spn3 changed val do updatePreview()
    on spn4 changed val do updatePreview()
    on onLinear changed state do updatePreview()
    
    -- 鼠标滚轮控制事件
    on spn1 mouseWheel delta do
    (
        local step = 50  -- 虚线长度步长
        spn1.value = spn1.value + (if delta > 0 then step else -step)
        updatePreview()
    )
    
    on spn2 mouseWheel delta do
    (
        local step = 50  -- 采样间隔步长
        spn2.value = spn2.value + (if delta > 0 then step else -step)
        updatePreview()
    )
    
    on spn3 mouseWheel delta do
    (
        local step = 10  -- 线条宽度步长
        spn3.value = spn3.value + (if delta > 0 then step else -step)
        updatePreview()
    )
    
    on spn4 mouseWheel delta do
    (
        local step = 5   -- 线条厚度步长
        spn4.value = spn4.value + (if delta > 0 then step else -step)
        updatePreview()
    )
    
    on spnOffset mouseWheel delta do
    (
        local step = if ds_translateOffset then 50 else 0.05  -- 平移模式50，旋转模式0.05（相当于5度）
        spnOffset.value = spnOffset.value + (if delta > 0 then step else -step)
        ds_offsetDistance = spnOffset.value
        if ds_previewEnabled and selection.count > 0 then
            updatePreview()
    )
    
    on spnQuadSize mouseWheel delta do
    (
        local step = 1   -- 四边形化大小步长
        spnQuadSize.value = spnQuadSize.value + (if delta > 0 then step else -step)
    )
    
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
         rdoMode.state = 1  -- 虚线模式
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
         
         updateUIState()
         
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
         rdoMode.state = 1  -- 虚线模式
         spn1.value = 50
         spn2.value = 101
         spn3.value = 520
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 40
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         updateUIState()
         
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
         rdoMode.state = 1  -- 虚线模式
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
         
         updateUIState()
         
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
         rdoMode.state = 1  -- 虚线模式
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
         
         updateUIState()
         
         -- 手动启用预览系统
         ds_previewEnabled = true
         if selection.count > 0 then
         (
             registerPreview()
             updatePreview()
         )
     )
    
    on btnPreset5 pressed do
     (
         -- 路口引导线：虚线长度：100 采样间隔：200，宽度：25
         rdoMode.state = 1  -- 虚线模式
         spn1.value = 100
         spn2.value = 200
         spn3.value = 25
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         updateUIState()
         
         -- 手动启用预览系统
         ds_previewEnabled = true
         if selection.count > 0 then
         (
             registerPreview()
             updatePreview()
         )
     )
    
    on btnPreset6 pressed do
     (
         -- 待转线：虚线长度：50 采样间隔：90，宽度：20
         rdoMode.state = 1  -- 虚线模式
         spn1.value = 50
         spn2.value = 90
         spn3.value = 20
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         updateUIState()
         
         -- 手动启用预览系统
         ds_previewEnabled = true
         if selection.count > 0 then
         (
             registerPreview()
             updatePreview()
         )
     )
     
    -- 实线预设
    on btnPreset7 pressed do
    (
        -- 实线：连续实线，宽度：100
        rdoMode.state = 2  -- 实线模式
        spn3.value = 100  -- 只设置线条宽度
        chkPlane.checked = true
        chkPreview.checked = true
        chkQuadify.checked = true
        spnQuadSize.value = 20
        spn4.enabled = false
        chkQuadify.enabled = true
        spnQuadSize.enabled = true
        
        updateUIState()
        
        -- 手动启用预览系统
        ds_previewEnabled = true
        if selection.count > 0 then
        (
            registerPreview()
            updatePreview()
        )
    )
    
    on btnPreset8 pressed do
    (
        -- 双实线：连续实线，宽度：150
        rdoMode.state = 2  -- 实线模式
        spn3.value = 150  -- 只设置线条宽度
        chkPlane.checked = true
        chkPreview.checked = true
        chkQuadify.checked = true
        spnQuadSize.value = 20
        spn4.enabled = false
        chkQuadify.enabled = true
        spnQuadSize.enabled = true
        
        updateUIState()
        
        -- 手动启用预览系统
        ds_previewEnabled = true
        if selection.count > 0 then
        (
            registerPreview()
            updatePreview()
        )
    )
    
    on btnPreset9 pressed do
    (
        -- 边界线：连续实线，宽度：200
        rdoMode.state = 2  -- 实线模式
        spn3.value = 200  -- 只设置线条宽度
        chkPlane.checked = true
        chkPreview.checked = true
        chkQuadify.checked = true
        spnQuadSize.value = 20
        spn4.enabled = false
        chkQuadify.enabled = true
        spnQuadSize.enabled = true
        
        updateUIState()
        
        -- 手动启用预览系统
        ds_previewEnabled = true
        if selection.count > 0 then
        (
            registerPreview()
            updatePreview()
        )
    )
    
    -- 偏移距离变化事件
    on spnOffset changed val do
    (
        ds_offsetDistance = val
        if ds_previewEnabled and selection.count > 0 then
            updatePreview()
    )
    
    -- 平移偏移复选框变化事件
     on chkRotateOffset changed state do
     (
         ds_translateOffset = state
         -- 动态更新标签和参数范围
         if state then
         (
             spnOffset.caption = "偏移距离："
             spnOffset.range = [-10000,10000,0]
         )
         else
         (
             spnOffset.caption = "旋转角度："
             spnOffset.range = [-360,360,0]  
         )
         
         if ds_previewEnabled and selection.count > 0 then
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
                    -- 使用统一的生成算法，根据模式调整参数
                    local solidValue = if ds_mode == 1 then spn1.value else 1000  -- 实线模式下solidLen参数不重要
                    local gapValue = if ds_mode == 1 then spn2.value else 0  -- 实线模式时间隔为0
                    local newObj = generateDashedShape shapeObj solidValue gapValue spn3.value spn4.value chkPlane.checked onLinear.checked
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