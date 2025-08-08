-- 车道导流线生成器 MVP版本
-- 在两个相交平面之间生成长条形锯齿箭头

global LaneArrowTool

-- 计算两个平面的相交线（通用版本）
fn findPlaneIntersection plane1 plane2 = (
    try (
        -- 通用方法获取平面信息
        local p1 = plane1.center
        local p2 = plane2.center
        
        -- 尝试获取法线方向（适用于不同类型的对象）
        local n1, n2
        
        -- 对于不同类型的对象尝试不同方法获取方向
        try (
            n1 = normalize(plane1.dir)
        ) catch (
            try (
                n1 = normalize(plane1.transform.row3)  -- Z轴方向
            ) catch (
                n1 = [0,0,1]  -- 默认向上
            )
        )
        
        try (
            n2 = normalize(plane2.dir)
        ) catch (
            try (
                n2 = normalize(plane2.transform.row3)  -- Z轴方向
            ) catch (
                n2 = [0,0,1]  -- 默认向上
            )
        )
        
        -- 计算相交线方向（两法线的叉积）
        local lineDir = cross n1 n2
        if length lineDir < 0.001 then (
            print "平面平行或方向相同，使用默认方向"
            lineDir = normalize(p2 - p1)  -- 使用连接方向作为默认
        ) else (
            lineDir = normalize lineDir
        )
        
        -- 计算相交线上的一点
        local midPoint = (p1 + p2) * 0.5
        
        print ("相交线方向: " + lineDir as string)
        print ("相交线中点: " + midPoint as string)
        
        return #(midPoint, lineDir)
        
    ) catch (
        print ("计算相交线失败: " + getCurrentException())
        return undefined
    )
)

-- 获取对象的大致尺寸（通用版本）
fn getObjectSize obj = (
    try (
        -- 尝试不同方法获取尺寸
        local objSize = [5.0, 5.0, 0.0]  -- 默认尺寸
        
        -- 方法1：如果有width/length属性
        try (
            if hasProperty obj #width and hasProperty obj #length then (
                objSize = [obj.width, obj.length, 0.0]
            )
        ) catch ()
        
        -- 方法2：通过bounding box计算
        try (
            local bbox = nodeGetBoundingBox obj obj.transform
            local size = bbox[2] - bbox[1]  -- max - min
            objSize = size
        ) catch ()
        
        print ("对象 " + obj.name + " 尺寸: " + objSize as string)
        return objSize
        
    ) catch (
        print ("获取对象尺寸失败，使用默认值")
        return [10.0, 10.0, 0.0]
    )
)

-- 获取两个对象重叠区域的边界（改进版本）
fn getOverlapBoundaries plane1 plane2 = (
    local size1 = getObjectSize plane1
    local size2 = getObjectSize plane2
    
    -- 计算重叠区域的大致范围
    local overlapWidth = (amin #(abs(size1.x), abs(size2.x))) * 0.5
    local overlapLength = (amin #(abs(size1.y), abs(size2.y))) * 0.5
    
    -- 确保最小值
    if overlapWidth < 2.0 then overlapWidth = 2.0
    if overlapLength < 5.0 then overlapLength = 5.0
    
    print ("重叠区域尺寸: " + [overlapWidth, overlapLength] as string)
    return #(overlapWidth, overlapLength)
)

-- 创建单个长条形锯齿箭头
fn createLaneArrow centerPos direction width:3.0 length:8.0 height:1.5 = (
    -- 计算垂直方向
    local up = [0, 0, 1]
    local perpDir = normalize(cross direction up)
    
    -- 创建长条形锯齿箭头的顶点
    local halfWidth = width * 0.5
    local halfLength = length * 0.5
    
    local verts = #(
        -- 箭头尖端
        centerPos + direction * halfLength,
        
        -- 箭头左侧底边
        centerPos + perpDir * halfWidth - direction * halfLength,
        centerPos - perpDir * halfWidth - direction * halfLength,
        
        -- 箭头右侧收缩点
        centerPos + perpDir * (halfWidth * 0.7) - direction * (halfLength * 0.3),
        centerPos - perpDir * (halfWidth * 0.7) - direction * (halfLength * 0.3)
    )
    
    -- 创建面（三角形构成锯齿状）
    local faces = #(
        [1, 4, 2],  -- 右侧三角
        [1, 3, 5],  -- 左侧三角  
        [2, 4, 5],  -- 中间四角面1
        [2, 5, 3]   -- 中间四角面2
    )
    
    -- 生成网格
    local arrowMesh = mesh vertices:verts faces:faces
    arrowMesh.name = "LaneArrow_" + (random 1 999) as string
    
    return arrowMesh
)

-- 从两个相交平面生成导流线
fn generateLaneArrowsFromPlanes plane1 plane2 count:3 spacing:10.0 = (
    if plane1 == undefined or plane2 == undefined then (
        messageBox "请选择两个平面对象"
        return false
    )
    
    -- 计算相交线
    local intersection = findPlaneIntersection plane1 plane2
    if intersection == undefined then (
        messageBox "两个平面不相交或平行"
        return false
    )
    
    local centerLine = intersection[1]
    local direction = intersection[2]
    
    -- 获取重叠区域边界
    local boundaries = getOverlapBoundaries plane1 plane2
    local laneWidth = boundaries[1] * 1.5  -- 箭头宽度基于重叠宽度
    
    local arrows = #()
    local startPos = centerLine - direction * (spacing * count * 0.5)
    
    for i = 1 to count do (
        local pos = startPos + direction * (spacing * i)
        local arrow = createLaneArrow pos direction width:laneWidth length:(spacing*0.8)
        append arrows arrow
    )
    
    print ("生成了 " + arrows.count as string + " 个导流线箭头")
    return arrows
)

-- 简单UI界面
rollout LaneArrowUI "导流线工具 MVP" width:220 height:200 (
    button btnSelect "选择两个相交平面" width:200 height:25
    label lblStatus "未选择平面" style_sunkenedge:true
    
    spinner spnCount "箭头数量:" range:[1,10,3] type:#integer width:190
    spinner spnSpacing "间距:" range:[5.0,50.0,12.0] type:#float width:190
    spinner spnWidth "宽度系数:" range:[0.5,3.0,1.0] type:#float width:190
    
    button btnGenerate "生成导流线" width:200 height:30
    button btnClear "清除箭头" width:95 height:20
    button btnClose "关闭" width:95 height:20
    
    local selectedPlanes = #()
    
    on btnSelect pressed do (
        if selection.count != 2 then (
            messageBox "请选择两个相交的平面对象"
        ) else (
            -- 不再检查特定类型，接受任何几何对象
            selectedPlanes = selection as array
            lblStatus.text = selectedPlanes[1].name + " + " + selectedPlanes[2].name
            print ("已选择对象: " + selectedPlanes[1].name + ", " + selectedPlanes[2].name)
            print ("对象1类型: " + (classOf selectedPlanes[1]) as string)
            print ("对象2类型: " + (classOf selectedPlanes[2]) as string)
        )
    )
    
    on btnGenerate pressed do (
        if selectedPlanes.count != 2 then (
            messageBox "请先选择两个相交的平面"
            return()
        )
        
        -- 创建撤销块
        with undo "生成车道导流线" on (
            local result = generateLaneArrowsFromPlanes selectedPlanes[1] selectedPlanes[2] count:spnCount.value spacing:spnSpacing.value
            if result != false then (
                messageBox ("成功生成 " + result.count as string + " 个导流线箭头")
                print "导流线生成完成"
            ) else (
                messageBox "生成失败，请检查平面是否相交"
            )
        )
    )
    
    on btnClear pressed do (
        -- 删除所有导流线箭头
        local arrowObjs = for obj in objects where (matchPattern obj.name pattern:"LaneArrow_*") collect obj
        if arrowObjs.count > 0 then (
            with undo "清除导流线" on (
                delete arrowObjs
                print ("清除了 " + arrowObjs.count as string + " 个导流线箭头")
            )
        ) else (
            messageBox "没有找到导流线箭头"
        )
    )
    
    on btnClose pressed do (
        destroyDialog LaneArrowTool
    )
)

-- 启动函数
fn startLaneArrowTool = (
    if LaneArrowTool != undefined then (
        destroyDialog LaneArrowTool
    )
    LaneArrowTool = LaneArrowUI
    createDialog LaneArrowTool
    print "导流线工具MVP已启动"
)

-- 自动启动
startLaneArrowTool()