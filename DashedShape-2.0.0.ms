-- 修复后的代码
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
global ds_copyCount = 0  -- 虚线复制数量
global ds_offsetDirection = 0  -- 偏移方向（-1=左侧，0=双向，1=右侧）

-------
-- 核心算法：虚线和实线的统一生成逻辑
-- 虚线模式：基于固定采样间隔的虚线分割逻辑
-- 实线模式：基于样条线本身结构的连续线段生成
-- solidLen: 虚线长度（距离单位）
-- gapDist: 采样点之间的距离间隔（距离单位，实线模式时为0）
-- useLinear: 是否使用线性模式
-- isRealSolid: 是否为真正的实线模式（区别于gapDist=0的连续虚线）
-------

-------
-- 公共函数：统一的细分采样逻辑
-- 抽取重复代码，提供统一的采样接口
-------
fn calculateSubdividedPoints splineObj splineIdx subdivisions =
(
    local segCount = numSegments splineObj splineIdx
    local points = #()
    
    for segIdx = 1 to segCount do
    (
        for subIdx = 1 to subdivisions do
        (
            local segStart = (segIdx - 1) as float / segCount as float
            local segEnd = segIdx as float / segCount as float
            local param = segStart + (subIdx - 1) as float * (segEnd - segStart) / subdivisions as float
            
            local pos = lengthInterp splineObj splineIdx param
            append points pos
        )
    )
    
    -- 添加最后一个点
    append points (lengthInterp splineObj splineIdx 1.0)
    return points
)

-------
-- 公共函数：计算细分段的边界点对
-- 用于平面生成和带宽线条绘制
-------
fn calculateSubdividedBoundaryPairs splineObj splineIdx subdivisions halfWidth =
(
    local segCount = numSegments splineObj splineIdx
    local leftVerts = #()
    local rightVerts = #()
    
    for segIdx = 1 to segCount do
    (
        for subIdx = 1 to subdivisions do
        (
            local segStart = (segIdx - 1) as float / segCount as float
            local segEnd = segIdx as float / segCount as float
            local subStart = segStart + (subIdx - 1) as float * (segEnd - segStart) / subdivisions as float
            local subEnd = segStart + subIdx as float * (segEnd - segStart) / subdivisions as float
            
            local startPos = lengthInterp splineObj splineIdx subStart
            local endPos = lengthInterp splineObj splineIdx subEnd
            
            local segmentDir = normalize (endPos - startPos)
            local perpDir = normalize (cross segmentDir [0,0,1])
            
            -- 只在第一次添加起始点
            if segIdx == 1 and subIdx == 1 then
            (
                append leftVerts (startPos - perpDir * halfWidth)
                append rightVerts (startPos + perpDir * halfWidth)
            )
            
            -- 总是添加结束点
            append leftVerts (endPos - perpDir * halfWidth)
            append rightVerts (endPos + perpDir * halfWidth)
        )
    )
    
    return #(leftVerts, rightVerts)
)
fn calculateDashedSegments splineObj splineIdx solidLen gapDist useLinear isRealSolid offsetDist translateOffset copyCount offsetDirection =
(
    local result = #()
    local splineLength = curveLength splineObj splineIdx
    
    if splineLength > 0 then
    (
        if isRealSolid then
        (
            -- 实线模式：保持原始样条线的完整曲线特征
            -- 在实线模式下，我们不需要分段，而是直接返回特殊标记
            -- 让generateDashedShape函数直接复制原始样条线
            append result #("COPY_ORIGINAL_SPLINE", splineIdx)
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
    
    -- 应用偏移处理（支持复制功能）
    if offsetDist != 0 and result.count > 0 and translateOffset then
    (
        local allCopies = #()  -- 存储所有复制的结果
        
        -- 如果copyCount为0，直接偏移原始线段
        if copyCount == 0 then
        (
            for i = 1 to result.count do
            (
                local segment = result[i]
                if segment[1] != "COPY_ORIGINAL_SPLINE" then
                (
                    local startPos = segment[1]
                    local endPos = segment[2]
                    
                    local segmentDir = normalize (endPos - startPos)
                    local perpDir = normalize (cross segmentDir [0,0,1])
                    
                    -- 根据方向参数调整偏移向量
                    if offsetDirection == 0 then
                    (
                        -- 中间按钮：同时向两边偏移（双向偏移）
                        local leftOffsetVector = perpDir * (-offsetDist)
                        local rightOffsetVector = perpDir * offsetDist
                        
                        -- 左侧偏移
                        local leftStartPos = startPos + leftOffsetVector
                        local leftEndPos = endPos + leftOffsetVector
                        result[i] = #(leftStartPos, leftEndPos)
                        
                        -- 右侧偏移（添加新的线段）
                        local rightStartPos = startPos + rightOffsetVector
                        local rightEndPos = endPos + rightOffsetVector
                        append result #(rightStartPos, rightEndPos)
                    )
                    else
                    (
                        -- 单向偏移（左或右）
                        local directionMultiplier = case offsetDirection of
                        (
                            (-1): -1.0  -- 左侧
                            1: 1.0      -- 右侧
                            default: 1.0
                        )
                        
                        -- 平移偏移：线段沿垂直方向偏移
                        local offsetVector = perpDir * (offsetDist * directionMultiplier)
                        local newStartPos = startPos + offsetVector
                        local newEndPos = endPos + offsetVector
                        
                        result[i] = #(newStartPos, newEndPos)
                    )
                )
            )
        )
        else
        (
            -- 复制模式：保留原始线段，生成偏移的复制
            -- 首先保留原始线段
            for segment in result do
                append allCopies segment
            
            -- 生成复制的偏移线段
            for copyIdx = 1 to copyCount do
            (
                local multiplier = if copyIdx == 1 then 1.0 else copyIdx  -- 第一次复制使用1倍距离，后续使用倍数距离
                
                for segment in result do
                (
                    if segment[1] != "COPY_ORIGINAL_SPLINE" then
                    (
                        local startPos = segment[1]
                        local endPos = segment[2]
                        
                        local segmentDir = normalize (endPos - startPos)
                        local perpDir = normalize (cross segmentDir [0,0,1])
                        
                        -- 根据方向参数调整偏移向量
                        if offsetDirection == 0 then
                        (
                            -- 中间按钮：同时向两边偏移（双向偏移）
                            local leftOffsetVector = perpDir * (-offsetDist * multiplier)
                            local rightOffsetVector = perpDir * (offsetDist * multiplier)
                            
                            -- 左侧偏移
                            local leftStartPos = startPos + leftOffsetVector
                            local leftEndPos = endPos + leftOffsetVector
                            append allCopies #(leftStartPos, leftEndPos)
                            
                            -- 右侧偏移
                            local rightStartPos = startPos + rightOffsetVector
                            local rightEndPos = endPos + rightOffsetVector
                            append allCopies #(rightStartPos, rightEndPos)
                        )
                        else
                        (
                            -- 单向偏移（左或右）
                            local directionMultiplier = case offsetDirection of
                            (
                                (-1): -1.0  -- 左侧
                                1: 1.0      -- 右侧
                                default: 1.0
                            )
                            
                            -- 计算偏移向量（使用倍数和方向）
                            local offsetVector = perpDir * (offsetDist * multiplier * directionMultiplier)
                            local newStartPos = startPos + offsetVector
                            local newEndPos = endPos + offsetVector
                            
                            append allCopies #(newStartPos, newEndPos)
                        )
                    )
                    else
                    (
                        -- 对实线模式的特殊处理
                        append allCopies segment
                    )
                )
            )
            
            -- 用所有复制替换原始结果
            result = allCopies
        )
    )
    else if offsetDist != 0 and result.count > 0 and not translateOffset then
    (
        -- 旋转偏移模式（保持原有逻辑）
        for i = 1 to result.count do
        (
            local segment = result[i]
            if segment[1] != "COPY_ORIGINAL_SPLINE" then
            (
                local startPos = segment[1]
                local endPos = segment[2]
                
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
                    local segments = calculateDashedSegments obj splineIdx solidLen gapLen useLinear isRealSolid ds_offsetDistance ds_translateOffset ds_copyCount ds_offsetDirection
                    local halfWidth = if lineWidth > 0 then lineWidth / 2.0 else 0.5
                    
                    -- 绘制每个线段或原始样条线
                    for segment in segments do
                    (
                        if segment[1] == "COPY_ORIGINAL_SPLINE" then
                        (
                            -- 实线模式：使用统一的采样函数
                            local sourceSplineIdx = segment[2]
                            local subdivisions = 3  -- 预览用的细分级别
                            
                            -- 使用公共函数获取所有采样点
                            local allPoints = calculateSubdividedPoints obj sourceSplineIdx subdivisions
                        
                        if generatePlane then
                        (
                            -- 绘制平面预览：使用统一的边界计算函数
                            local boundaryPairs = calculateSubdividedBoundaryPairs obj sourceSplineIdx subdivisions halfWidth
                            local leftPoints = boundaryPairs[1]
                            local rightPoints = boundaryPairs[2]
                            
                            -- 绘制左右边界线
                            if leftPoints.count > 1 then
                                gw.polyline leftPoints false
                            if rightPoints.count > 1 then
                                gw.polyline rightPoints false
                            
                            -- 绘制所有顶点的竖向连接线
                            if leftPoints.count > 0 and rightPoints.count > 0 then
                            (
                                for i = 1 to leftPoints.count do
                                (
                                    gw.polyline #(leftPoints[i], rightPoints[i]) false
                                )
                            )
                        )
                        else
                        (
                            -- 绘制线条预览
                            if lineWidth > 0 or lineThickness > 0 then
                            (
                                -- 使用统一的边界计算函数
                                local boundaryPairs = calculateSubdividedBoundaryPairs obj sourceSplineIdx subdivisions halfWidth
                                local leftPoints = boundaryPairs[1]
                                local rightPoints = boundaryPairs[2]
                                
                                -- 绘制左右边界线
                                if leftPoints.count > 1 then
                                    gw.polyline leftPoints false
                                if rightPoints.count > 1 then
                                    gw.polyline rightPoints false
                                
                                -- 绘制所有顶点的竖向连接线
                                if leftPoints.count > 0 and rightPoints.count > 0 then
                                (
                                    for i = 1 to leftPoints.count do
                                    (
                                        gw.polyline #(leftPoints[i], rightPoints[i]) false
                                    )
                                )
                            )
                            else
                            (
                                -- 简单线条预览：直接绘制连续线条
                                if allPoints.count > 1 then
                                    gw.polyline allPoints false
                            )
                        )
                        )
                        else
                        (
                            -- 虚线模式：绘制线段
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
        )
        
        gw.enlargeUpdateRect #whole
        gw.updateScreen()
    )
)







-------
-- 生成函数：创建实际的几何体
-------

-- 创建平面几何体的函数（优化弧度处理 + 顶点焊接）
fn createPlaneFromSpline sourceSpline planeWidth =
(
    try
    (
        local verts = #()
        local faces = #()
        
        for splineIdx = 1 to numSplines sourceSpline do
        (
            local halfWidth = planeWidth / 2.0
            local subdivisions = 4  -- 每个原始段细分为4段
            
            -- 使用统一的边界计算函数
            local boundaryPairs = calculateSubdividedBoundaryPairs sourceSpline splineIdx subdivisions halfWidth
            local leftVerts = boundaryPairs[1]
            local rightVerts = boundaryPairs[2]
            
            -- 将左右顶点添加到总顶点数组中
            local startVertIndex = verts.count + 1
            for i = 1 to leftVerts.count do
            (
                append verts leftVerts[i]
                append verts rightVerts[i]
            )
            
            -- 创建面片（连接相邻的顶点对）
            -- 顶点存储格式：left1, right1, left2, right2, left3, right3, ...
            for i = 1 to (leftVerts.count - 1) do
            (
                -- 计算当前和下一个顶点对的索引
                local currentLeftIndex = startVertIndex + (i - 1) * 2      -- 当前左顶点
                local currentRightIndex = startVertIndex + (i - 1) * 2 + 1  -- 当前右顶点
                local nextLeftIndex = startVertIndex + i * 2               -- 下一个左顶点
                local nextRightIndex = startVertIndex + i * 2 + 1          -- 下一个右顶点
                
                -- 创建四边形的两个三角形面
                -- 顶点顺序：当前左、当前右、下一个右、下一个左
                local face1 = [currentLeftIndex, currentRightIndex, nextRightIndex]  -- 左下、右下、右上
                local face2 = [currentLeftIndex, nextRightIndex, nextLeftIndex]      -- 左下、右上、左上
                
                append faces face1
                append faces face2
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
        local segments = calculateDashedSegments newObj splineIdx solidLen gapLen useLinear isRealSolid ds_offsetDistance ds_translateOffset ds_copyCount ds_offsetDirection
        
        -- 处理线段或原始样条线复制
        for segment in segments do
        (
            if segment[1] == "COPY_ORIGINAL_SPLINE" then
            (
                -- 实线模式：直接复制原始样条线的完整结构
                local sourceSplineIdx = segment[2]
                addNewSpline resultShape
                local targetSplineIdx = numSplines resultShape
                
                -- 复制所有节点及其属性
                local knotCount = numKnots newObj sourceSplineIdx
                for knotIdx = 1 to knotCount do
                (
                    local knotPos = getKnotPoint newObj sourceSplineIdx knotIdx
                    local knotType = getKnotType newObj sourceSplineIdx knotIdx
                    local inVec = getInVec newObj sourceSplineIdx knotIdx
                    local outVec = getOutVec newObj sourceSplineIdx knotIdx
                    
                    addKnot resultShape targetSplineIdx #corner #line knotPos
                    setInVec resultShape targetSplineIdx knotIdx inVec
                    setOutVec resultShape targetSplineIdx knotIdx outVec
                )
                
                -- 设置样条线的封闭状态
                close resultShape targetSplineIdx (isClosed newObj sourceSplineIdx)
            )
            else
            (
                -- 虚线模式：创建线段
                local startPos = segment[1]
                local endPos = segment[2]
                
                addNewSpline resultShape
                local currentSplineIdx = numSplines resultShape
                addKnot resultShape currentSplineIdx #corner #line startPos
                addKnot resultShape currentSplineIdx #corner #line endPos
            )
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
    else
    (
        -- 设置渲染属性（包括实线和虚线模式）
        resultShape.render_renderable = true
        resultShape.render_displayRenderMesh = true
        resultShape.render_rectangular = true
        resultShape.render_viewport_rectangular = true
        
        -- 确保宽度和厚度设置正确应用
        if lineWidth > 0 then
            resultShape.render_width = lineWidth
        if lineThickness > 0 then
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
    spinner 'spnCopyCount' "" pos:[155,182] width:30 height:20 range:[0,10,0] type:#integer visible:false
    checkbox 'onLinear' "线性" pos:[10,207] width:40 height:22 align:#left
    checkbox 'chkPlane' "生成平面" pos:[80,207] width:70 height:22 align:#left
    checkbox 'chkRotateOffset' "平移偏移" pos:[10,232] width:70 height:22 align:#left
    checkbox 'chkPreview' "显示预览" pos:[80,232] width:70 height:22 align:#left
    checkbox 'chkQuadify' "四边形化" pos:[10,257] width:70 height:22 align:#left
    button 'btnOffsetLeft' "<" pos:[120,257] width:20 height:22 align:#left visible:false
    button 'btnOffsetCenter' "-" pos:[143,257] width:25 height:22 align:#left visible:false
    button 'btnOffsetRight' ">" pos:[171,257] width:20 height:22 align:#left visible:false
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
            ds_offsetDistance = spnOffset.value
            ds_translateOffset = chkRotateOffset.checked
            ds_copyCount = spnCopyCount.value  -- 更新复制数量
            -- ds_offsetDirection 已经在按钮事件中更新
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
                
                -- 显示虚线预设按钮，隐藏实线预设按钮，并重新排列位置
                btnPreset1.visible = true
                btnPreset1.pos = [17,312]
                btnPreset2.visible = true
                btnPreset2.pos = [75,312]
                btnPreset3.visible = true
                btnPreset3.pos = [133,312]
                btnPreset4.visible = true
                btnPreset4.pos = [17,342]
                btnPreset5.visible = true
                btnPreset5.pos = [75,342]
                btnPreset6.visible = true
                btnPreset6.pos = [133,342]
                btnPreset7.visible = false
                btnPreset8.visible = false
                btnPreset9.visible = false
            )
            2: -- 实线模式
            (
                spn1.caption = "（无需设置）"
                spn1.enabled = false  -- 实线模式下不需要分段长度参数
                spn2.enabled = false  -- 实线模式下不需要采样间隔参数
                spn3.caption = "线条宽度："
                ds_mode = 2
                
                -- 隐藏虚线预设按钮，显示实线预设按钮，并重新排列位置
                btnPreset1.visible = false
                btnPreset2.visible = false
                btnPreset3.visible = false
                btnPreset4.visible = false
                btnPreset5.visible = false
                btnPreset6.visible = false
                btnPreset7.visible = true
                btnPreset7.pos = [17,312]
                btnPreset8.visible = true
                btnPreset8.pos = [75,312]
                btnPreset9.visible = true
                btnPreset9.pos = [133,312]
            )
        )
        
        -- 根据偏移模式更新偏移参数的标签
        if chkRotateOffset.checked then
        (
            spnOffset.caption = "偏移距离："
            spnCopyCount.visible = true   -- 平移模式显示复制数量输入框
            -- 显示方向控制按钮
            btnOffsetLeft.visible = true
            btnOffsetCenter.visible = true
            btnOffsetRight.visible = true
        )
        else
        (
            spnOffset.caption = "旋转角度："
            spnCopyCount.visible = false  -- 旋转模式隐藏复制数量输入框
            -- 隐藏方向控制按钮
            btnOffsetLeft.visible = false
            btnOffsetCenter.visible = false
            btnOffsetRight.visible = false
        )
        
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
        ds_copyCount = spnCopyCount.value
        
        -- 初始化方向按钮状态（默认双向偏移）
        ds_offsetDirection = 0
        -- 使用文本来表示按钮状态
        btnOffsetLeft.text = "<"      -- 未选中
        btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
        btnOffsetRight.text = ">"     -- 未选中
        
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
         spn4.value = 0     -- 明确设置厚度为0
         spnOffset.value = 0 -- 明确设置偏移为0
         spnCopyCount.value = 0 -- 明确设置复制数量为0
         onLinear.checked = false -- 明确设置线性模式
         chkRotateOffset.checked = false -- 明确设置偏移模式
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 重置方向控制
         ds_offsetDirection = 0
         btnOffsetLeft.text = "<"      -- 未选中
         btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
         btnOffsetRight.text = ">"     -- 未选中
         
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
         spn4.value = 0     -- 明确设置厚度为0
         spnOffset.value = 0 -- 明确设置偏移为0
         spnCopyCount.value = 0 -- 明确设置复制数量为0
         onLinear.checked = false -- 明确设置线性模式
         chkRotateOffset.checked = false -- 明确设置偏移模式
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 40
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 重置方向控制
         ds_offsetDirection = 0
         btnOffsetLeft.text = "<"      -- 未选中
         btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
         btnOffsetRight.text = ">"     -- 未选中
         
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
         spn4.value = 0     -- 明确设置厚度为0
         spnOffset.value = 0 -- 明确设置偏移为0
         spnCopyCount.value = 0 -- 明确设置复制数量为0
         onLinear.checked = false -- 明确设置线性模式
         chkRotateOffset.checked = false -- 明确设置偏移模式
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 重置方向控制
         ds_offsetDirection = 0
         btnOffsetLeft.text = "<"      -- 未选中
         btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
         btnOffsetRight.text = ">"     -- 未选中
         
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
         spn4.value = 0     -- 明确设置厚度为0
         spnOffset.value = 0 -- 明确设置偏移为0
         spnCopyCount.value = 0 -- 明确设置复制数量为0
         onLinear.checked = false -- 明确设置线性模式
         chkRotateOffset.checked = false -- 明确设置偏移模式
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 重置方向控制
         ds_offsetDirection = 0
         btnOffsetLeft.text = "<"      -- 未选中
         btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
         btnOffsetRight.text = ">"     -- 未选中
         
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
         spn4.value = 0     -- 明确设置厚度为0
         spnOffset.value = 0 -- 明确设置偏移为0
         spnCopyCount.value = 0 -- 明确设置复制数量为0
         onLinear.checked = false -- 明确设置线性模式
         chkRotateOffset.checked = false -- 明确设置偏移模式
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 重置方向控制
         ds_offsetDirection = 0
         btnOffsetLeft.text = "<"      -- 未选中
         btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
         btnOffsetRight.text = ">"     -- 未选中
         
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
         spn4.value = 0     -- 明确设置厚度为0
         spnOffset.value = 0 -- 明确设置偏移为0
         spnCopyCount.value = 0 -- 明确设置复制数量为0
         onLinear.checked = false -- 明确设置线性模式
         chkRotateOffset.checked = false -- 明确设置偏移模式
         chkPlane.checked = true
         chkPreview.checked = true
         chkQuadify.checked = true
         spnQuadSize.value = 20
         spn4.enabled = false
         chkQuadify.enabled = true
         spnQuadSize.enabled = true
         
         -- 重置方向控制
         ds_offsetDirection = 0
         btnOffsetLeft.text = "<"      -- 未选中
         btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
         btnOffsetRight.text = ">"     -- 未选中
         
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
        spn4.value = 0     -- 明确设置厚度为0
        spnOffset.value = 0 -- 明确设置偏移为0
        spnCopyCount.value = 0 -- 明确设置复制数量为0
        onLinear.checked = false -- 明确设置线性模式
        chkRotateOffset.checked = false -- 明确设置偏移模式
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
        spn4.value = 0     -- 明确设置厚度为0
        spnOffset.value = 0 -- 明确设置偏移为0
        spnCopyCount.value = 0 -- 明确设置复制数量为0
        onLinear.checked = false -- 明确设置线性模式
        chkRotateOffset.checked = false -- 明确设置偏移模式
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
        spn4.value = 0     -- 明确设置厚度为0
        spnOffset.value = 0 -- 明确设置偏移为0
        spnCopyCount.value = 0 -- 明确设置复制数量为0
        onLinear.checked = false -- 明确设置线性模式
        chkRotateOffset.checked = false -- 明确设置偏移模式
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
    
    -- 复制数量变化事件
    on spnCopyCount changed val do
    (
        ds_copyCount = val
        if ds_previewEnabled and selection.count > 0 then
            updatePreview()
    )
    
    -- 平移偏移复选框变化事件
     on chkRotateOffset changed state do
     (
         ds_translateOffset = state
         
         -- 控制复制数量输入框的显示/隐藏
         spnCopyCount.visible = state
         
         -- 控制方向按钮的显示/隐藏
         btnOffsetLeft.visible = state
         btnOffsetCenter.visible = state
         btnOffsetRight.visible = state
         
         -- 根据项目规范，切换模式时清零值
         if state then
         (
             spnOffset.caption = "偏移距离："
             spnOffset.range = [-10000,10000,0]  -- 切换到平移模式时清零
             spnCopyCount.value = 0              -- 清零复制数量
             ds_offsetDirection = 0              -- 重置为双向偏移
             -- 设置默认选中双向按钮
             btnOffsetLeft.text = "<"      -- 未选中
             btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
             btnOffsetRight.text = ">"     -- 未选中
         )
         else
         (
             spnOffset.caption = "旋转角度："
             spnOffset.range = [-360,360,0]      -- 切换到旋转模式时清零
         )
         
         -- 更新全局变量
         ds_offsetDistance = spnOffset.value
         ds_copyCount = spnCopyCount.value
         
         if ds_previewEnabled and selection.count > 0 then
             updatePreview()
     )
     
    -- 方向控制按钮事件
    on btnOffsetLeft pressed do
    (
        ds_offsetDirection = 1  -- 左侧偏移
        btnOffsetLeft.text = "[<]"     -- 选中（方括号表示）
        btnOffsetCenter.text = "↔"     -- 未选中
        btnOffsetRight.text = ">"     -- 未选中
        updatePreview()
    )
    
    on btnOffsetCenter pressed do
    (
        ds_offsetDirection = 0   -- 双向偏移（同时向两边）
        btnOffsetLeft.text = "<"      -- 未选中
        btnOffsetCenter.text = "[↔]"   -- 选中（双向箭头表示双向偏移）
        btnOffsetRight.text = ">"     -- 未选中
        updatePreview()
    )
    
    on btnOffsetRight pressed do
    (
        ds_offsetDirection = -1   -- 右侧偏移
        btnOffsetLeft.text = "<"      -- 未选中
        btnOffsetCenter.text = "↔"     -- 未选中
        btnOffsetRight.text = "[>]"    -- 选中（方括号表示）
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