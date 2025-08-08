(
-- 地形填充脚本主程序
-- 获取脚本文件路径
global mlpt_populate_path =getFilenamePath(getSourceFileName())
--------------------------------

-- 调试模式设置
-- 覆盖路径设置（调试用）
--mlpt_populate_path =mlpt_populate_path+"\\setup\\Scripts\\Populate-Terrain\\"
--------------------------------

	-- 缓存 meshop/polyOp 结构体...提高速度并减少内存泄漏
meshopgetEdgesUsingVert=meshop.getEdgesUsingVert
meshopGetVertsUsingEdge=meshop.getVertsUsingEdge
polyOpGetEdgeFaces=polyOp.getEdgeFaces
polyOpGetEdgesUsingVert=polyOp.getEdgesUsingVert
polyOpGetVert=polyOp.getVert
polyOpSetVert=polyOp.setVert
polyOpGetVertsUsingEdge=polyOp.getVertsUsingEdge
polyOpGetVertsUsedOnlyByFaces=polyOp.getVertsUsedOnlyByFaces
polyOpGetFaceDeg=polyOp.getFaceDeg
polyOpDeleteVerts=polyOp.deleteVerts

-- 恢复编辑模式
resumeediting()
	
-- 脚本版本号
local populate_version=1.5
-- 配置文件位置
local ini_location="$plugcfg/populate-terrain.ini"

-- 脚本标题
local populate_title="Terrain tool_"+(populate_version as string)

-- 全局对话框和界面变量
global mlpt_dialog_populate,mlpt_ro_common,mlpt_ro_postprocessing,mlpt_ro_about,mlpt_ro_options
-- 当前操作对象
global mlpt_currentObject
	
-- 尝试销毁已存在的对话框
try(destroyDialog mlpt_dialog_populate) catch()

-- 错误消息定义
local fileMissingMessage="文件缺失 - 请重新安装 Populate:Terrain"
-- 用于在脚本创建的修改器中存储ID的随机应用数据ID
local randomAppDataID=3757904
-- 用于在基础节点中存储设置的随机应用数据ID
local randomAppDataSettings=3757905
-- 用于选择的节点，通过名称/字符串查找它们，即使重命名等
local randomAppDataNodeID=3757906
-- 绿色主题颜色
local mlpt_green=color 110 228 0
-- 返回值变量
local mlpt_returnValue

-- 会话设置结构体定义
global struct_settings 
struct struct_settings (dialog_width,dialog_height,subdivs_x,subdivs_y,size_x,size_y,percent_x,percent_y,square,subdiv_mode,\
	bordermode,meshingmethod,debug_mode,version,adaptive_refinement,adaptive_refinement_vertspercell,adaptive_refinement_maxsubdivs,automethod,\
	relax_on,turbosmooth_on,relax_value,relax_iterations,turbosmooth_iterations,turbosmooth_isolinedisplay,cookie_cut,cookie_cut_nodehandle,cookie_invert,\
	slicer_rows,slicer_columns,slicer_length,slicer_width,slicer_units,slicer_tolerance,slicer_threshold,slicer_integerSnap,slicer_precisionMode,slicer_previewEnabled,slicer_precisionType)
	
-- 全局设置变量
global mlptSettings
-- 强制重置设置以确保使用新的结构体定义
mlptSettings=undefined
-- 如果设置版本不匹配或不存在版本属性，则重置设置（来自旧版本时重置）
if not isProperty mlptSettings "version" or mlptSettings.version!=populate_version do mlptSettings=undefined
-- 如果设置未定义，则初始化默认设置
if (mlptSettings==undefined) do mlptSettings = struct_settings dialog_width:348 dialog_height:526 \
	subdivs_x:10 subdivs_y:10 size_x:10 size_y:10 percent_x:10 percent_y:10 square:false subdiv_mode:1 \
	bordermode:1 meshingmethod:1 debug_mode:false version:populate_version \
	adaptive_refinement:false adaptive_refinement_vertspercell:4 adaptive_refinement_maxsubdivs:8 automethod:true \
	relax_on:false turbosmooth_on:false relax_value:0.5 relax_iterations:100 turbosmooth_iterations:1 turbosmooth_isolinedisplay:false \
	cookie_cut:true cookie_cut_nodehandle:undefined cookie_invert:false \
	slicer_rows:2 slicer_columns:2 slicer_length:100 slicer_width:100 slicer_units:1 slicer_tolerance:0.001 slicer_threshold:1000000 slicer_integerSnap:true slicer_precisionMode:false slicer_previewEnabled:false slicer_precisionType:1

-- 全局对话框位置变量
global mlpt_dialogPos
-- 如果对话框位置未定义，设置为unsupplied，否则使用"undefined"位置创建对话框时会崩溃
if mlpt_dialogPos==undefined do mlpt_dialogPos=unsupplied

-- 如果对话框模式未定义，设置为紧凑模式
if mlpt_dialogMode==undefined then mlpt_dialogMode=#compact
-- 最后子卷展栏索引
local LastSubRollout = 1
-- 界面颜色设置
local lvBackcolor = ((colorman.getColor #rollupTitleFace )*255) as color
local lvActivecolor = ((colorman.getColor #activeCommand )*255) as color
local lvTextcolor = ((colorman.getColor #windowText )*255) as color
local lvWindowcolor = ((colorman.getColor #window )*255) as color
-- 如果窗口颜色过亮，设置为白色
if lvWindowcolor.r>=225 then lvWindowcolor=white

-- 样条线过滤器函数：不选择当前已选中的对象
fn pickFiltSpline o = (isShapeObject o and selection[1]!=o)
-- 几何体过滤器函数：选择几何体类或形状对象
fn pickFiltGeometry o = (superClassOf o == GeometryClass or isShapeObject o)

	-- 获取对象的动画句柄和应用数据标记
	-- 返回的字符串可以存储在应用数据、ini、xml等文件中
fn getHandleFromNode o appDataChannel:randomAppDataNodeID = if isValidNode o do
(
	local randomClassID
		-- 测试节点中是否存在应用数据标记ID
	local alreadyStamped=getAppdata o appDataChannel
	if alreadyStamped!=undefined then try (local alreadyUsedClassID=execute alreadyStamped); catch(alreadyStamped=undefined)
	-- 如果找到标记ID，使用现有ID
	if alreadyStamped!=undefined and isKindOf alreadyUsedClassID array then randomClassID=alreadyUsedClassID
	else 
	(
		randomClassID=genClassID returnValue:true
		-- 将随机类ID存储到选择的对象中，以便在重命名、合并等操作后仍能找到它
		setAppData o appDataChannel (randomClassID as string)
	)

	local thisHandle=GetHandleByAnim o
	
	-- 返回句柄数据作为字符串
	#(thisHandle,randomClassID)

)
	-- 从getHandleFromNode生成的句柄字符串中查找对象
fn getNodeFromHandle handleArray appDataChannel:randomAppDataNodeID=
(
	local returnNode=undefined
	if isKindOf handleArray array do 
	(
		local handle=handleArray[1] as IntegerPtr
		local randomClassID=handleArray[2]
		-- 通过动画句柄查找节点
		local foundObj=GetAnimByHandle handle
		-- 如果找到，测试节点中是否存在应用数据标记ID
		if isValidNode foundObj do
		(
			-- 节点找到，存储以供返回
			if (getAppdata foundObj appDataChannel)==randomClassID do returnNode=foundObj
		)

		-- 如果未找到节点，搜索整个场景中的应用数据标记ID
		for i in objects while returnNode==undefined do
		(
			if (getAppdata i appDataChannel)==(randomClassID as string) do returnNode=i
		)
	)
	returnNode
)

-------
-- GW 绘制方法
-------
/*
	-- denisT编写的函数
      global easyViewSelectionBBox
      unRegisterRedrawViewsCallback easyViewSelectionBBox
      
      fn easyViewSelectionBBox =
      (
      	nodes = for node in selection where iskindof node GeometryClass collect node
      	if nodes.count > 0 do
      	(
      		view = viewport.activeViewport
      		local bmin = [1e9,1e9,0], bmax = [-1e9,-1e9,0]
      
      		gw.setTransform (matrix3 1)
      		transPoint = gw.hTransPoint
      		for node in nodes do
      		(
      			mesh = snapshotasmesh node
      			for v=1 to mesh.numverts do
      			(
      				vp = transPoint (GetVert mesh v)
      				if vp.x < bmin.x do bmin.x = vp.x
      				if vp.x > bmax.x do bmax.x = vp.x
      				if vp.y < bmin.y do bmin.y = vp.y
      				if vp.y > bmax.y do bmax.y = vp.y
      			)
      			free mesh
      		)
      		w = (bmax.x - bmin.x) as integer
      		h = (bmax.y - bmin.y) as integer
      		rect = box2 bmin.x bmin.y w h
      		gw.hPolyline #(bmin, point3 bmax.x bmin.y 0, bmax, point3 bmin.x bmax.y 0) on rgb:#(orange,orange,orange,orange)
      		gw.hText (bmin + [5,h-20,0]) ("Size: [" + (w as string) + ", " + (h as string) + "]") color:orange
      		gw.enlargeUpdateRect rect
      		gw.updateScreen()
      	)
      )
      registerRedrawViewsCallback easyViewSelectionBBox
      completeRedraw()
	  */

-- 边界网格绘制相关全局变量
global mlpt_drawBoundingGrid, mlpt_initBoundingGrid, mlpt_subdivsX, mlpt_subdivsY
-- 统一预览系统和ModelSlicer集成相关全局变量
global mlpt_activePreviewTool = #none  -- #terrain, #slicer
global mlpt_slicer_selectedObj = undefined
global mlpt_slicer_previewEnabled = false  
global mlpt_slicer_rows = 2, mlpt_slicer_columns = 2
global mlpt_slicer_previewColor = color 255 0 0  -- 红色预览线条
global mlpt_slicer_drawSliceGrid, mlpt_slicer_initSliceGrid

-- 绘制边界网格函数
fn mlpt_drawBoundingGrid o subdivs_x subdivs_y=
(
	-- 创建变换矩阵
	local tm = preRotateZ (matrix3 1) 0  
	-- 获取对象边界框
	local bbox = nodeGetBoundingBox o tm
	local a=bbox[1]
	local b=bbox[2]
	local size=(b-a)
	local w=size[1]
	local l=size[2]
	local h=size[3]
	
	-- 设置图形窗口变换
	gw.setTransform(tm)
		
	-- 线条数组
	local lineArrays = #()
	a_orig=copy a
	-- 绘制X方向的分割线
	for i=0 to subdivs_x do
	(
		append lineArrays #([a.x,a.y,a.z] ,[a.x, a.y, b.z], [a.x, b.y, b.z],[a.x, b.y, a.z])
		a.x+=(w/subdivs_x)
	)
	a=a_orig
	-- 绘制Y方向的分割线
	for i=0 to subdivs_y do
	(
		append lineArrays #([a.x,a.y,a.z] ,[a.x, a.y, b.z],[b.x, a.y, b.z],[b.x, a.y, a.z])
		a.y+=(l/subdivs_y)
	)
	-- 设置线条颜色为绿色
	gw.setColor #line mlpt_green
	-- 绘制所有线条
	for l in lineArrays do gw.polyline l true 
	-- 更新整个显示区域
	gw.enlargeUpdateRect #whole
	gw.updateScreen() 
)

-- ModelSlicer预览功能：绘制切割网格预览
fn mlpt_slicer_drawSliceGrid obj rows columns =
(
    if obj != undefined and isValidNode obj then
    (
        local tm = matrix3 1
        local bbox = nodeGetBoundingBox obj tm
        local minPt = bbox[1]
        local maxPt = bbox[2]
        local size = maxPt - minPt
        local width = size[1]
        local length = size[2]
        local height = size[3]
        
        -- 将预览网格绘制在模型最高点上方
        local previewZ = maxPt.z + (height * 0.1)
        
        gw.setTransform(tm)
        
        local lineArrays = #()
        
        -- 确保行列数大于0，避免除零错误
        if rows <= 0 then rows = 1
        if columns <= 0 then columns = 1
        
        -- 绘制垂直线（列分割线）
        for i = 0 to columns do
        (
            local x = minPt.x + (width / columns) * i
            append lineArrays #([x, minPt.y, previewZ], [x, maxPt.y, previewZ])
        )
        
        -- 绘制水平线（行分割线）
        for i = 0 to rows do
        (
            local y = minPt.y + (length / rows) * i
            append lineArrays #([minPt.x, y, previewZ], [maxPt.x, y, previewZ])
        )
        
        -- 设置预览线条颜色并绘制
        gw.setColor #line mlpt_slicer_previewColor
        for lineArray in lineArrays do gw.polyline lineArray false
        gw.enlargeUpdateRect #whole
        gw.updateScreen()
    )
)
-- 初始化边界网格（注释掉的版本：影响所有选中对象）
--fn mlpt_initBoundingGrid=for o in selection do mlpt_drawBoundingGrid o mlpt_subdivsX mlpt_subdivsY
-- 初始化边界网格（仅当选中一个对象时显示）
fn mlpt_initBoundingGrid=if selection.count==1 do for o in selection where (superClassOf o == GeometryClass or isShapeObject o) do mlpt_drawBoundingGrid o mlpt_subdivsX mlpt_subdivsY

-- ModelSlicer预览功能：初始化网格预览
fn mlpt_slicer_initSliceGrid =
(
    try
    (
        if mlpt_slicer_previewEnabled and mlpt_slicer_selectedObj != undefined and isValidNode mlpt_slicer_selectedObj then
        (
            if (superClassOf mlpt_slicer_selectedObj == GeometryClass or isShapeObject mlpt_slicer_selectedObj) then
            (
                mlpt_slicer_drawSliceGrid mlpt_slicer_selectedObj mlpt_slicer_rows mlpt_slicer_columns
            )
        )
    )
    catch
    (
        -- 如果出现错误，静默处理，避免中断预览功能
    )
)

-- 统一预览系统初始化函数
fn mlpt_initUnifiedPreview =
(
    try
    (
        case mlpt_activePreviewTool of
        (
            #terrain: mlpt_initBoundingGrid()
            #slicer: mlpt_slicer_initSliceGrid()
        )
    )
    catch
    (
        -- 错误处理
    )
)
-- 注册边界网格预览
fn register_boundinggrid=
(
	-- 设置当前预览工具为地形工具
	mlpt_activePreviewTool = #terrain
	-- 取消注册之前的回调函数
	unregisterRedrawViewsCallback mlpt_initUnifiedPreview
	-- 注册统一预览回调函数
	registerRedrawViewsCallback mlpt_initUnifiedPreview 
	-- 重绘视图
	redrawviews()
)

-- 注册ModelSlicer预览
fn mlpt_slicer_registerPreview =
(
    -- 设置当前预览工具为切片工具
    mlpt_activePreviewTool = #slicer
    -- 取消注册之前的回调函数
    unregisterRedrawViewsCallback mlpt_initUnifiedPreview
    -- 注册统一预览回调函数
    registerRedrawViewsCallback mlpt_initUnifiedPreview
    -- 重绘视图
    redrawviews()
)

-- 取消注册边界网格预览
fn unregister_boundinggrid=
(
	-- 设置预览工具为无
	mlpt_activePreviewTool = #none
	-- 取消注册回调函数
	unregisterRedrawViewsCallback mlpt_initUnifiedPreview
	-- 强制完全重绘（Max 2011修复）
	forcecompleteredraw()
)

-- 注销ModelSlicer预览
fn mlpt_slicer_unregisterPreview =
(
    -- 设置预览工具为无
    mlpt_activePreviewTool = #none
    -- 取消注册回调函数
    unregisterRedrawViewsCallback mlpt_initUnifiedPreview
    -- 强制完全重绘
    forcecompleteredraw()
)
-------
-- GW绘制方法结束
-------

-------
-- ModelSlicer 核心功能函数
-------

-- 单位转换函数：将用户输入的值转换为系统单位（使用双精度）
fn mlpt_slicer_convertToSystemUnits value unitIndex =
(
    local doubleValue = value as double
    case unitIndex of
    (
        1: doubleValue  -- 系统单位，不转换
        2: (
            -- 毫米转系统单位
            case units.SystemType of
            (
                #millimeters: doubleValue
                #centimeters: doubleValue / 10.0d0
                #meters: doubleValue / 1000.0d0
                #inches: doubleValue / 25.4d0
                #feet: doubleValue / 304.8d0
                default: doubleValue
            )
        )
        3: (
            -- 厘米转系统单位
            case units.SystemType of
            (
                #millimeters: doubleValue * 10.0d0
                #centimeters: doubleValue
                #meters: doubleValue / 100.0d0
                #inches: doubleValue / 2.54d0
                #feet: doubleValue / 30.48d0
                default: doubleValue
            )
        )
        4: (
            -- 米转系统单位
            case units.SystemType of
            (
                #millimeters: doubleValue * 1000.0d0
                #centimeters: doubleValue * 100.0d0
                #meters: doubleValue
                #inches: doubleValue / 0.0254d0
                #feet: doubleValue / 0.3048d0
                default: doubleValue
            )
        )
        5: (
            -- 英寸转系统单位
            case units.SystemType of
            (
                #millimeters: doubleValue * 25.4d0
                #centimeters: doubleValue * 2.54d0
                #meters: doubleValue * 0.0254d0
                #inches: doubleValue
                #feet: doubleValue / 12.0d0
                default: doubleValue
            )
        )
        6: (
            -- 英尺转系统单位
            case units.SystemType of
            (
                #millimeters: doubleValue * 304.8d0
                #centimeters: doubleValue * 30.48d0
                #meters: doubleValue * 0.3048d0
                #inches: doubleValue * 12.0d0
                #feet: doubleValue
                default: doubleValue
            )
        )
        default: doubleValue
    )
)

-- 从系统单位转换为显示单位（使用双精度）
fn mlpt_slicer_convertFromSystemUnits value unitIndex =
(
    local doubleValue = value as double
    case unitIndex of
    (
        1: doubleValue  -- 系统单位，不转换
        2: (
            -- 系统单位转毫米
            case units.SystemType of
            (
                #millimeters: doubleValue
                #centimeters: doubleValue * 10.0d0
                #meters: doubleValue * 1000.0d0
                #inches: doubleValue * 25.4d0
                #feet: doubleValue * 304.8d0
                default: doubleValue
            )
        )
        3: (
            -- 系统单位转厘米
            case units.SystemType of
            (
                #millimeters: doubleValue / 10.0d0
                #centimeters: doubleValue
                #meters: doubleValue * 100.0d0
                #inches: doubleValue * 2.54d0
                #feet: doubleValue * 30.48d0
                default: doubleValue
            )
        )
        4: (
            -- 系统单位转米
            case units.SystemType of
            (
                #millimeters: doubleValue / 1000.0d0
                #centimeters: doubleValue / 100.0d0
                #meters: doubleValue
                #inches: doubleValue * 0.0254d0
                #feet: doubleValue * 0.3048d0
                default: doubleValue
            )
        )
        5: (
            -- 系统单位转英寸
            case units.SystemType of
            (
                #millimeters: doubleValue / 25.4d0
                #centimeters: doubleValue / 2.54d0
                #meters: doubleValue / 0.0254d0
                #inches: doubleValue
                #feet: doubleValue * 12.0d0
                default: doubleValue
            )
        )
        6: (
            -- 系统单位转英尺
            case units.SystemType of
            (
                #millimeters: doubleValue / 304.8d0
                #centimeters: doubleValue / 30.48d0
                #meters: doubleValue / 0.3048d0
                #inches: doubleValue / 12.0d0
                #feet: doubleValue
                default: doubleValue
            )
        )
        default: doubleValue
    )
)

-- 生成随机颜色
fn mlpt_slicer_getRandomColor = 
(
    -- 生成高饱和度、中等亮度的随机颜色
    local h = random 0.0 1.0
    local s = random 0.7 1.0
    local v = random 0.5 0.9
    
    -- 将HSV转换为RGB
    local hi = floor(h * 6)
    local f = h * 6 - hi
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    
    local r, g, b
    
    case hi of
    (
        0: (r = v; g = t; b = p)
        1: (r = q; g = v; b = p)
        2: (r = p; g = v; b = t)
        3: (r = p; g = q; b = v)
        4: (r = t; g = p; b = v)
        default: (r = v; g = p; b = q)
    )
    
    -- 返回颜色
    return color (r*255) (g*255) (b*255)
)

-- 将对象裁剪到指定的整数边界
fn mlpt_slicer_cropObjectToIntegerBounds obj minX maxX minY maxY =
(
    try
    (
        if obj != undefined and isValidNode obj then
        (
            -- 确保对象是可编辑多边形
            if (classOf obj != Editable_Poly) then
                convertToPoly obj
            
            -- 将边界转换为整数
            local intMinX = floor (minX + 0.5)
            local intMaxX = floor (maxX + 0.5)
            local intMinY = floor (minY + 0.5)
            local intMaxY = floor (maxY + 0.5)
            
            -- 找到需要删除的顶点（完全在边界外的）
            local vertsToDelete = #()
            for v = 1 to obj.verts.count do
            (
                local vertPos = obj.verts[v].pos
                if vertPos.x < intMinX or vertPos.x > intMaxX or vertPos.y < intMinY or vertPos.y > intMaxY then
                (
                    append vertsToDelete v
                )
            )
            
            -- 删除边界外的顶点
            if vertsToDelete.count > 0 then
            (
                polyop.deleteVerts obj vertsToDelete
            )
            
            -- 将剩余顶点限制在边界内并整数化
            for v = 1 to obj.verts.count do
            (
                local vertPos = obj.verts[v].pos
                local newPos = vertPos
                
                -- 限制并整数化坐标
                if newPos.x < intMinX then newPos.x = intMinX
                if newPos.x > intMaxX then newPos.x = intMaxX
                if newPos.y < intMinY then newPos.y = intMinY
                if newPos.y > intMaxY then newPos.y = intMaxY
                
                -- 整数化Z坐标
                newPos.z = floor (newPos.z + 0.5)
                
                polyop.setVert obj v newPos
            )
            
            -- 清理孤立顶点
            polyop.deleteIsoVerts obj
            
            -- 更新对象
            update obj
        )
    )
    catch
    (
        local errorMsg = getCurrentException()
        print "========== ModelSlicer cropObjectToIntegerBounds 错误 =========="
        print ("时间: " + (localTime as string))
        print ("错误信息: " + errorMsg)
        print ("对象名称: " + (if obj != undefined then obj.name else "未定义"))
        print ("边界参数: minX=" + (minX as string) + ", maxX=" + (maxX as string) + ", minY=" + (minY as string) + ", maxY=" + (maxY as string))
        print "=============================================================="
    )
)

-- 将顶点坐标整数化
fn mlpt_slicer_snapVerticesToIntegers obj =
(
    try
    (
        if obj != undefined and isValidNode obj then
        (
            -- 确保对象是可编辑多边形
            if (classOf obj != Editable_Poly) then
                convertToPoly obj
            
            -- 检查精度类型和是否启用整数对齐
            -- 精度类型：1=小数精度，2=整数精度
            if mlptSettings.slicer_precisionType == 2 and mlptSettings.slicer_integerSnap then
            (
                local largeModelThreshold = mlptSettings.slicer_threshold
                
                -- 将所有顶点坐标整数化（仅当不是大模型时）
                for v = 1 to obj.verts.count do
                (
                    local vertPos = obj.verts[v].pos
                    
                    -- 只对小于阈值的坐标进行整数化
                    if abs(vertPos.x) < largeModelThreshold and abs(vertPos.y) < largeModelThreshold then
                    (
                        local newPos = [floor(vertPos.x + 0.5), floor(vertPos.y + 0.5), floor(vertPos.z + 0.5)]
                        polyop.setVert obj v newPos
                    )
                )
            )
            
            -- 更新对象
            update obj
        )
    )
    catch
    (
        local errorMsg = getCurrentException()
        print "========== ModelSlicer snapVerticesToIntegers 错误 =========="
        print ("时间: " + (localTime as string))
        print ("错误信息: " + errorMsg)
        print ("对象名称: " + (if obj != undefined then obj.name else "未定义"))
        if obj != undefined and isValidNode obj then
        (
            print ("顶点数量: " + (obj.verts.count as string))
        )
        print "=========================================================="
    )
)

-- 精确设置对象边界到指定的尺寸
fn mlpt_slicer_setObjectToExactBounds obj minX maxX minY maxY =
(
    try
    (
        if obj != undefined and isValidNode obj then
        (
            -- 确保对象是可编辑多边形
            if (classOf obj != Editable_Poly) then
                convertToPoly obj
            
            -- 获取当前对象边界，根据精度模式选择计算方式
            local currentBounds = obj.max - obj.min
            local currentMin = obj.min
            
            -- 计算缩放和偏移，根据精度模式使用不同精度
            local scaleX, scaleY, offsetX, offsetY
            if mlptSettings.slicer_precisionMode then
            (
                -- 高精度模式：使用双精度计算
                scaleX = ((maxX as double) - (minX as double)) / (currentBounds.x as double)
                scaleY = ((maxY as double) - (minY as double)) / (currentBounds.y as double)
                offsetX = (minX as double) - (currentMin.x as double) * scaleX
                offsetY = (minY as double) - (currentMin.y as double) * scaleY
            )
            else
            (
                -- 标准模式：使用单精度计算
                scaleX = (maxX - minX) / currentBounds.x
                scaleY = (maxY - minY) / currentBounds.y
                offsetX = minX - currentMin.x * scaleX
                offsetY = minY - currentMin.y * scaleY
            )
            
            -- 获取用户设置的容差和阈值
            local tolerance = mlptSettings.slicer_tolerance
            local largeModelThreshold = mlptSettings.slicer_threshold
            local enableIntegerSnap = mlptSettings.slicer_integerSnap
            
            -- 变换所有顶点到精确边界
            for v = 1 to obj.verts.count do
            (
                local vertPos = obj.verts[v].pos
                local newPos = vertPos
                
                -- 应用缩放和偏移
                if mlptSettings.slicer_precisionMode then
                (
                    newPos.x = (vertPos.x as double) * scaleX + offsetX
                    newPos.y = (vertPos.y as double) * scaleY + offsetY
                )
                else
                (
                    newPos.x = vertPos.x * scaleX + offsetX
                    newPos.y = vertPos.y * scaleY + offsetY
                )
                
                -- 确保边界顶点精确对齐，使用用户设置的容差
                if abs(newPos.x - minX) < tolerance then newPos.x = minX
                if abs(newPos.x - maxX) < tolerance then newPos.x = maxX
                if abs(newPos.y - minY) < tolerance then newPos.y = minY
                if abs(newPos.y - maxY) < tolerance then newPos.y = maxY
                
                -- 根据精度类型和设置决定是否进行整数化
                -- 精度类型：1=小数精度，2=整数精度
                if mlptSettings.slicer_precisionType == 2 and enableIntegerSnap and (abs(newPos.x) < largeModelThreshold and abs(newPos.y) < largeModelThreshold) then
                (
                    newPos.x = floor (newPos.x + 0.5)
                    newPos.y = floor (newPos.y + 0.5)
                    newPos.z = floor (newPos.z + 0.5)
                )
                
                polyop.setVert obj v newPos
            )
            
            -- 更新对象
            update obj
        )
    )
    catch
    (
        local errorMsg = getCurrentException()
        print "========== ModelSlicer setObjectToExactBounds 错误 =========="
        print ("时间: " + (localTime as string))
        print ("错误信息: " + errorMsg)
        print ("对象名称: " + (if obj != undefined then obj.name else "未定义"))
        print ("边界参数: minX=" + (minX as string) + ", maxX=" + (maxX as string) + ", minY=" + (minY as string) + ", maxY=" + (maxY as string))
        if obj != undefined and isValidNode obj then
        (
            local currentBounds = obj.max - obj.min
            print ("当前对象边界: " + (currentBounds as string))
            print ("顶点数量: " + (obj.verts.count as string))
        )
        print "=============================================================="
    )
)

-- 优化的切割方法
fn mlpt_slicer_optimizedSlice obj rows columns deleteOrig useCustomSize customLength customWidth =
(
    try
    (
        local resultObjects = #()
        
        -- 获取对象边界，使用双精度
        local objBounds = obj.max - obj.min
        local startPos = obj.min
        
        -- 计算每个切片的尺寸，使用双精度计算
        local sliceWidth, sliceHeight
        
        if useCustomSize then
        (
            -- 将用户输入的自定义尺寸转换为系统单位（双精度）
            sliceWidth = mlpt_slicer_convertToSystemUnits (customLength as double) mlptSettings.slicer_units
            sliceHeight = mlpt_slicer_convertToSystemUnits (customWidth as double) mlptSettings.slicer_units
            
            -- 重新计算行列数以适应自定义尺寸，使用双精度计算
            columns = if sliceWidth > 0 then (ceil ((objBounds.x as double) / sliceWidth)) as integer else 1
            rows = if sliceHeight > 0 then (ceil ((objBounds.y as double) / sliceHeight)) as integer else 1
            
            -- 限制最大行列数
            if columns > 10000 then columns = 10000
            if rows > 10000 then rows = 10000
        )
        else
        (
            -- 使用均等分割，使用双精度计算确保精确尺寸
            sliceWidth = (objBounds.x as double) / (columns as double)
            sliceHeight = (objBounds.y as double) / (rows as double)
        )
        
        -- 制作一个副本作为工作对象
        local workObj = copy obj
        convertToPoly workObj
        
        -- 计算总切片数
        local totalSlices = rows * columns
        local currentSlice = 0
        
        -- 为了提高性能，我们从最后一个开始，逐个分离
        for row = rows to 1 by -1 do
        (
            for col = columns to 1 by -1 do
            (
                try
                (
                    -- 更新进度
                    currentSlice += 1
                    
                    if (row == 1 and col == 1) then
                    (
                        -- 最后一个网格，不需要再分离
                        workObj.name = obj.name + "_R" + row as string + "C" + col as string
                        -- 计算最后一个网格的边界，使用精确的双精度计算
                        local minX = startPos.x + ((col-1) as double) * sliceWidth
                        local maxX = startPos.x + (col as double) * sliceWidth
                        local minY = startPos.y + ((row-1) as double) * sliceHeight
                        local maxY = startPos.y + (row as double) * sliceHeight
                        -- 精确设置到边界框
                        mlpt_slicer_setObjectToExactBounds workObj minX maxX minY maxY
                        -- 将顶点坐标整数化
                        try (mlpt_slicer_snapVerticesToIntegers workObj) catch ()
                        append resultObjects workObj
                    )
                    else
                    (
                        -- 计算当前网格的边界，使用精确的双精度计算避免累积误差
                        local minX = startPos.x + ((col-1) as double) * sliceWidth
                        local maxX = startPos.x + (col as double) * sliceWidth
                        local minY = startPos.y + ((row-1) as double) * sliceHeight
                        local maxY = startPos.y + (row as double) * sliceHeight
                        
                        -- 选择在当前网格内的面
                        local facesToDetach = #()
                        
                        -- 更高效的方法：使用面的中心点判断
                        for f = 1 to workObj.faces.count do
                        (
                            local faceCenter = polyop.getFaceCenter workObj f
                            
                            -- 检查面中心是否在当前网格内
                            if faceCenter.x >= minX and faceCenter.x <= maxX and faceCenter.y >= minY and faceCenter.y <= maxY then
                            (
                                append facesToDetach f
                            )
                        )
                        
                        -- 如果找到了面，就分离它们
                        if facesToDetach.count > 0 then
                        (
                            -- 分离选中的面为新对象
                            local newObjName = obj.name + "_R" + row as string + "C" + col as string
                            polyop.detachFaces workObj facesToDetach delete:true asNode:true name:newObjName
                            
                            -- 获取刚创建的对象并添加到结果数组
                            local newObj = getNodeByName newObjName
                            if newObj != undefined then
                            (
                                -- 精确设置到边界框（已包含整数化）
                                mlpt_slicer_setObjectToExactBounds newObj minX maxX minY maxY
                                append resultObjects newObj
                            )
                        )
                    )
                )
                catch
                (
                    local errorMsg = getCurrentException()
                    print "========== ModelSlicer optimizedSlice 单个切片错误 =========="
                    print ("时间: " + (localTime as string))
                    print ("错误信息: " + errorMsg)
                    print ("当前切片: 行" + (row as string) + " 列" + (col as string))
                    print ("切片尺寸: 宽=" + (sliceWidth as string) + ", 高=" + (sliceHeight as string))
                    print "=========================================================="
                )
            )
        )
        
        -- 删除原始对象（如果需要）
        if deleteOrig then
        (
            delete obj
        )
        
        return resultObjects
    )
    catch
    (
        local errorMsg = getCurrentException()
        print "========== ModelSlicer optimizedSlice 主函数错误 =========="
        print ("时间: " + (localTime as string))
        print ("错误信息: " + errorMsg)
        print ("对象名称: " + (if obj != undefined then obj.name else "未定义"))
        print ("切割参数: 行=" + (rows as string) + ", 列=" + (columns as string))
        print ("自定义尺寸: 长=" + (customLength as string) + ", 宽=" + (customWidth as string))
        print ("使用自定义尺寸: " + (useCustomSize as string))
        if obj != undefined and isValidNode obj then
        (
            local objBounds = obj.max - obj.min
            print ("对象边界: " + (objBounds as string))
        )
        print "=========================================================="
        return #()
    )
)

-------
-- ModelSlicer 核心功能函数结束
-------

-- 更新所有卷展栏设置
fn updateAllRolloutSettings overwrite:false=
(
	mlpt_ro_common.updateSettings overwrite:overwrite
	mlpt_ro_postprocessing.updateSettings overwrite:overwrite
)
-- 将设置存储到修改器中
fn storeSettingsIntoModifier currentObject=	if isValidNode currentObject do 
(
	local thisModifier=currentObject.modifiers[1]
	-- 检查populate:terrain修改器是否已存在
	if ((validModifier currentObject thisModifier) and (getAppData thisModifier randomAppDataID)=="1") do
	(
		-- 将当前设置存储到修改器中
		setAppData thisModifier randomAppDataSettings (mlptSettings as string)
	)
)

-- 获取当前对象
fn getCurrentObject=
(
	local currentlySelected=selection[1]
	
	--trimShape=getNodeFromHandle mlptSettings.cookie_cut_nodehandle
	
	-- 根据选择数量处理
	case selection.count of
	(
		0: try(mlpt_dialog_populate.lbl_status.text="Select a geometry or spline object"); catch();
		1: if isValidNode currentlySelected do if (superClassOf currentlySelected == GeometryClass or isShapeObject currentlySelected) do currentlySelected
		default: try(mlpt_dialog_populate.lbl_status.text="Please change selection to a single object"); catch();
	)
)
	--get world aligned bounding box, returns o.x, o.y, o.z
fn getBBox o=if isValidNode o do
(
	local tm = preRotateZ (matrix3 1) 0  
	local bbox = nodeGetBoundingBox o tm
	bbox[2]-bbox[1]
)
	--function by DenisT
	--pre:0.1 ... 6.66->6.7
 fn roundFloat d pre:1 =
 (
  d = (d as float)/pre
  v = if (d - (v1 = floor d)) > ((v2 = ceil d) - d) then v2 else v1 
  v*pre
 )
 
-------
-- selection change callback
-------
global mlpt_objChanged
fn mlpt_objChanged thisEvent thisNodes =
(
	--format "% %\n" thisEvent thisNodes
	--a=getCurrentObject()
	--print a
	mlpt_currentObject=getCurrentObject()
	
	-- 检查并清理无效的 selectedObj 变量
	if selectedObj != undefined and not isValidNode selectedObj then
	(
		selectedObj = undefined
		mlpt_slicer_selectedObj = undefined
		-- 更新模型切割器界面显示
		if mlpt_ro_modelslicer != undefined then
		(
			mlpt_ro_modelslicer.lbl_selectedModel.text = "未选择模型"
			mlpt_ro_modelslicer.lbl_status.text = "所选模型已被删除，请重新选择"
		)
	)
	
	if mlpt_dialog_populate!=undefined do mlpt_dialog_populate.dialog_refresh()
)
	--remove previous callback
fn mlpt_objChangedRemove no_gc:false=
(
	mlpt_callbackSelectionChanged=undefined
	mlpt_callbackDeleted=undefined
	mlpt_callbackNameChanged=undefined
	mlpt_callbackAdded=undefined
	if not no_gc do gc lite:true
)
mlpt_objChangedRemove()
global mlpt_callbackSelectionChanged=NodeEventCallback selectionChanged:mlpt_objChanged mouseUp:false
global mlpt_callbackDeleted=NodeEventCallback deleted:mlpt_objChanged mouseUp:false
global mlpt_callbackNameChanged=NodeEventCallback nameChanged:mlpt_objChanged mouseUp:false
global mlpt_callbackAdded=NodeEventCallback added:mlpt_objChanged mouseUp:false
-------
-- selection change callback end
-------


local startTime

--------------------------------------------
-- 地形创建函数
--------------------------------------------

-- 重绘方法
local oldPanel
	
fn stopRedraw=
(
	commandHWND = (windows.getChildHWND #max "Command Panel") --尝试按名称查找命令面板
	if commandHWND != undefined and classOf commandHWND==Array then commandHWND=commandHWND[1]
	else 
	(		--如果按名称查找失败（本地化max版本），则以不同方式查找命令面板
		first_child_hwnd = for i in (windows.getchildrenhwnd #max) where i[4] == "SysTabControl32" do exit with i[1]
		if classOf(first_child_hwnd)==IntegerPtr then commandHWND = uiaccessor.getparentwindow first_child_hwnd
		if commandHWND==undefined do commandHWND = windows.getmaxhwnd() --如果没有命令面板，尝试查找整个max窗口
	)
	if commandHWND !=undefined do windows.sendmessage commandHWND 0xB 0 0
)
fn resumeRedraw=
(
	commandHWND = (windows.getChildHWND #max "Command Panel")
	if commandHWND != undefined and classOf commandHWND==Array then commandHWND=commandHWND[1]
	else 
	(
		first_child_hwnd = for i in (windows.getchildrenhwnd #max) where i[4] == "SysTabControl32" do exit with i[1]
		if classOf(first_child_hwnd)==IntegerPtr then commandHWND = uiaccessor.getparentwindow first_child_hwnd
		if commandHWND==undefined do commandHWND = windows.getmaxhwnd() --如果没有命令面板，尝试查找整个max窗口
	)
	if commandHWND !=undefined do windows.sendmessage commandHWND 0xB 1 0
)
fn stopRedrawPanel=
(
	oldPanel = getCommandPanelTaskMode() --记住旧的命令面板选项卡
	stopRedraw()
	setCommandPanelTaskMode mode:#create
)
fn resumeRedrawPanel=
(
	if oldPanel!=undefined do setCommandPanelTaskMode oldPanel --切换回之前的命令面板选项卡
	if selection==undefined do select selection --命令面板重绘修复
	resumeRedraw()
	if getCommandPanelTaskMode()==#modify do --重绘修复
	(
		if $!=undefined and $.modifiers[1]!=undefined do modPanel.setCurrentObject $.modifiers[1]
	)
	--classof $  --重绘修复
	--forcecompleteredraw()
)
-- 重绘方法结束

-- 创建地形对象
fn createTerrain thisTerrainSpline normalizeLength:10 = if isShapeObject thisTerrainSpline do
(
	mod_normalizeSpline=Normalize_Spl length:normalizeLength
	addModifier thisTerrainSpline mod_normalizeSpline
	thisTerrain=Terrain name:"mlpt_tempmesh_terr" --retriangulate:true
	terrainOps.addOperand thisTerrain thisTerrainSpline
	--delete thisTerrainSpline
	thisTerrain
)

-- 布尔相交运算
fn booleanIntersect a b engine:#boolean=
(
	case engine of
	(
		#boolean:
		(
			boolObj.createBooleanObject a
			boolObj.setBoolOp a 5
			boolObj.setBoolCutType a 4
			boolObj.SetOperandB a b 4 5
			boolObj.setOptimize a true
		)
		#proboolean:	--在填充模式下效果很好，有时在地形上不行？
		(
			ProBoolean.createBooleanObject a b 1 2 1
			ProBoolean.SetCookieCut a true
			ProBoolean.SetPlanarEdgeRemoval a 2 --边缘移除3很糟糕..在边缘制造额外的顶点!!
		)
		#procutter: --在岛屿=填充模式下不工作？在地形上效果好？
		(
			ProCutter.CreateCutter a 4 true false false false false
			ProCutter.AddStocks a b 1 1
			ProCutter.SetPlanarEdgeRemoval a 3
		)
	)	
)
-- 布尔减法运算
fn booleanSubstract a b engine:#proboolean _invert:false=
(
	if _invert then method=1 else method=2
	case engine of
	(
		#proboolean:	--在填充模式下效果很好，有时在地形上不行？
		(
			ProBoolean.createBooleanObject a b method 2 1
			ProBoolean.SetCookieCut a true
			ProBoolean.SetPlanarEdgeRemoval a 2 --边缘移除3很糟糕..在边缘制造额外的顶点!!
		)
	)	
)
	
-- 平整网格
fn flattenMesh o=
(
	local thisPlane = [0,0,1] --平面法线
	meshop.moveVertsToPlane o #all thisPlane 0.0 
)


--返回在世界空间中不向上指向的面的位数组
fn collectFlippedMeshFaces obj flipOnlyIfAllFacesPointingDownwards:false fixFlippedFaces:false deleteFlippedFaces:false=	--flip: 翻转找到的面
(
	local obj_faces=obj.faces as bitarray
	local flipped_faces = #{}
	for f in obj_faces where (in coordsys world getFaceNormal obj f).z < 0 do append flipped_faces f
		
		--如果所有面都向下指向，则翻转它们
	if flipOnlyIfAllFacesPointingDownwards and (obj_faces.numberset==flipped_faces.numberset) then meshop.flipNormals obj flipped_faces
	else if fixFlippedFaces then meshop.flipNormals obj flipped_faces
	else if deleteFlippedFaces then meshop.deleteFaces obj flipped_faces delIsoVerts:true
	else flipped_faces
)
	--移除顶点，保持面完整
fn removePolyVerts obj vertices=
(		
		--检查对象是否为可编辑多边形
	if classOf obj == editable_poly then
	(
		if selection.count!=1 and selection[1]!=obj do select obj --仅在未选中时选择...性能考虑!
		setCommandPanelTaskMode mode:#modify
		polyOp.setvertselection obj vertices
		--subobjectlevel = 1 --切换到顶点级别
		obj.Remove() --移除当前选择
		--subobjectLevel = 0
	)
		--检查对象是否为应该更新的可编辑多边形修改器
	else if classOf obj.modifiers[1] == Edit_Poly then 
	(
		local thisModifier=obj.modifiers[1]
		if selection.count!=1 and selection[1]!=obj then select obj --仅在未选中时选择...性能考虑!
		setCommandPanelTaskMode mode:#modify
		thisModifier.SetSelection #Vertex vertices
		--subobjectlevel = 1 --切换到顶点级别
		thisModifier.buttonOp #removeVertex --移除当前选择
		
			--循环移除顶点操作直到没有变化
		local previousVertexCount=0
		while (local thisCount=(thisModifier.GetSelection #Vertex).numberset) > 0 and previousVertexCount!=thisCount do
		(
			previousVertexCount=thisCount
			thisModifier.buttonOp #removeVertex --移除剩余顶点？参见terrain_quad.max
		)
		
		if (thisModifier.GetSelection #Vertex).numberset > 0 do thisModifier.buttonOp #DeleteVertex --好主意？如果循环移除仍有剩余顶点则删除

		--thisModifier.SetSelection #Vertex #{}
		--subobjectLevel = 0

	)
	else false
)
--查找开放边缘上未连接到其他面的顶点
fn collectOpenEdgeVertices obj deleteVerts:false keepQuads:true=	--deleteVerts: 删除找到的顶点
(
	local vertices = #{}
	local borderEdges = polyOp.getOpenEdges obj
	local facesToSearch = #{}
	for i in borderEdges do
	(
		join facesToSearch (polyOpGetEdgeFaces obj i as bitarray) --收集通过开放边缘的面
	)
	for f in facesToSearch do
	(
		local thisFaceOpenEdgeVerts=polyOpGetVertsUsedOnlyByFaces obj f	--慢？
		local isNotQuad=if keepQuads then (polyOpGetFaceDeg obj f)>4 else true
		if isNotQuad do join vertices thisFaceOpenEdgeVerts
	)
	
	vertsOnStraightLine=#{}
	for v in vertices do
	(
		--获取使用该顶点的边以检查数量
		nVerts = (polyOpGetEdgesUsingVert obj v) as array
		if nVerts.count == 2 do --如果只找到两条边，则
		(
			--获取第一条边的顶点
			local edge1verts = (polyOpGetVertsUsingEdge obj nVerts[1]) as array
			--计算第一条边中两个顶点定义的向量
			local vector1 = (polyOpGetVert obj edge1verts[1]) - (polyOpGetVert obj edge1verts[2])
			--获取第二条边的顶点
			local edge2verts = (polyOpGetVertsUsingEdge obj nVerts[2]) as array
			--计算第二条边中两个顶点定义的向量
			local vector2 = (polyOpGetVert obj edge2verts[1]) - (polyOpGetVert obj edge2verts[2])
			--计算两个标准化向量之间的角度
			local a = acos (dot (normalize vector1) (normalize vector2))
			--如果角度小于阈值（将0.01更改为您想要的任何阈值！）
				
			if a < 60.0 or a > 120.0 do	--60而不是0.01。不是寻找直线而是角落
			(
				append vertsOnStraightLine v
			)
		)
	)
	
	vertices=vertices*vertsOnStraightLine --相交两个顶点集合
	
	if deleteVerts then removePolyVerts obj vertices
	else vertices	--返回找到的顶点数组
)


--在originalObj上创建编辑多边形修改器，删除原始几何体并将resultPlane附加到它
--updateModifier 更新堆栈第一位置的现有编辑多边形修改器
fn createAndAttachToEditPolyMod originalObj resultPlane updateModifier:undefined tagWithAppData:false =
(
	if updateModifier!=undefined and validModifier originalObj updateModifier then
	(
		local mod_editPoly=updateModifier
		mod_editPoly.enabled=true
	)
	else
	(
		local mod_editPoly=edit_poly()
		mod_editPoly.name="Populate:Terrain"
		addModifier originalObj mod_editPoly
	)
	if tagWithAppData do setAppData mod_editPoly randomAppDataID "1" --标记修改器
	if selection.count!=1 and selection[1]!=originalObj do select originalObj --仅在未选中时选择...性能考虑！

	--modPanel.setCurrentObject mod_editPoly --激活修改器 

	local this_faces=originalObj.faces as bitarray

	setCommandPanelTaskMode mode:#modify --使修改器面板对maxscript"可见"
	--subObjectLevel = 4
	mod_editPoly.SetSelection #Face this_faces
	mod_editPoly.ButtonOp #DeleteFace
	mod_editPoly.attach resultPlane --编辑多边形节点:originalObj
	mod_editPoly.SetSelection #Face #{}
	--subObjectLevel = 0
)
	--循环遍历所有子对象样条线，如果开放则关闭
fn closeSubObjectSplines spl checkOnly:false=
(
	local returnValue=true
	if (classOf spl == Splineshape and classOf spl ==line) then
	(
		if checkOnly then
		(
			for i=1 to (numSplines spl) do if not isClosed spl i do returnValue=false
		)
		else 
		(
			for i=1 to (numSplines spl) do if not isClosed spl i do 
			(
				close spl i
				updateShape spl
			)
		)
	)
	else returnValue=true
	returnValue
)
	--转换样条线 
fn prepareSplineForTerrain originalObj shapeMode:#auto normalizeLength:30=
(
	--print originalObj.height
	local obj
	case shapeMode of
	(
		#terrainCompound:
		(
			tempObj=copy originalObj
			obj=createTerrain tempObj normalizeLength:normalizeLength
			delete tempObj
		)
		#fill:
		(
			local isShapeClosed=closeSubObjectSplines originalObj checkOnly:true
			if isShapeClosed then obj=snapshot originalObj name:"mlpt_tempmesh"
			else
			(
				tempObj=copy originalObj
				closeSubObjectSplines tempObj
				obj=snapshot tempObj
				delete tempObj
			)
			
		)
	)
	obj --返回
)
	--为布尔运算创建实体挤出对象
fn createBooleanSolid obj height mode:#splinefrompolyextrude cap:true=
(
	if height<0.1 do height=1.0	--防止零高度外壳
	case mode of
	(
		#shell:
		(
			local mod_shell = shell Bevel:false Segments:1 innerAmount:0 outerAmount:height overrideInnerMatID:false overrideOuterMatID:false overrideMatID:false autosmooth:false autoSmoothAngle:45 overrideSmoothingGroup:false edgeMapping:1 selectEdgeFaces:false selectInnerFaces:false selectOuterFaces:false straightenCorners:false
			addModifier obj mod_shell
		)
		#splinefrompolyextrude:
		(
			if isValidNode $mlpt_tempplane_createBooleanSolidShape do delete $mlpt_tempplane_createBooleanSolidShape
			convertToPoly obj
			local borderEdges = polyOp.getOpenEdges obj
			polyOp.createShape obj borderEdges name:"mlpt_tempplane_createBooleanSolidShape" smooth:false
			local borderSpline=$mlpt_tempplane_createBooleanSolidShape
			
			--检查所有子对象样条线是否已关闭以进行挤出
			closeSubObjectSplines borderSpline
			
			local mod_extrude = extrude amount:height segs:1 capStart:cap capEnd:cap capType:0 output:1 matIDs:off smooth:off mapCoords:false realWorldMapSize:false
			addModifier borderSpline mod_extrude
			delete obj
			obj=borderSpline
		)
		#splineextrude:
		(
				--检查所有子对象样条线是否已关闭以进行挤出
			closeSubObjectSplines borderSpline
			local mod_extrude = extrude amount:height segs:1 capStart:cap capEnd:cap capType:0 output:1 matIDs:off smooth:off mapCoords:false realWorldMapSize:false
			addModifier obj mod_extrude
		)
	)
	convertToMesh obj
	CenterPivot obj
	obj.position.z-=height/2	--移动到中间高度，更适合布尔运算
	obj --返回对象
)

	--沿世界Z轴将obj包裹到target_obj上
	--期望输入MESH返回POLY
function zWrapMesh obj target_obj fixLeftoverVerts:true keepShootingIfRayFailed:true deleteMissedVerts:false doubleSidedHitTest:false bbox: snapToVertsPositions: = 
(

	local zeroHeight=bbox[1].z
	local verts = obj.verts as bitarray --#{1..(getNumVerts obj)}
	local leftover_verts = #{}
	if deleteMissedVerts do local vertsToDelete=#{}
	
	rm = RayMeshGridIntersect() --创建参考目标的实例 
		
	rm.Initialize 10 --初始化体素网格大小为10x10x10 
	rm.addNode target_obj
	rm.buildGrid()
	
	numberOfRayIterations=0
	
	for i in verts do
	( 
		vertPos = getVert obj i
		vertPos0=[vertPos.x,vertPos.y,zeroHeight]
		rayTarget = normalize (vertPos0 - vertPos)
		
		theHitsCount=rm.intersectRay vertPos rayTarget doubleSidedHitTest
			
		if theHitsCount>0 then --如果第一条射线击中表面
		(
			closestHit=rm.getClosestHit()
			dist=rm.getHitDist closestHit
			newVertPos=vertPos+(rayTarget*dist)
			setVert obj i newVertPos
		)
		else if keepShootingIfRayFailed then --继续尝试
		(	--疯狂的射线向量弯曲以找到邻近区域
			local searchRadius=1e-006
			local maxSearchRadius=0.1
			local stepSize=10
			local	searchRays=#()
			local keepSearching=true
			do
			(
				rayArrayEnd=	 #([vertPos.x+searchRadius,vertPos.y+searchRadius,zeroHeight],
										[vertPos.x-searchRadius,vertPos.y+searchRadius,zeroHeight],
										[vertPos.x+searchRadius,vertPos.y-searchRadius,zeroHeight],
										[vertPos.x-searchRadius,vertPos.y-searchRadius,zeroHeight],
										[vertPos.x,vertPos.y+searchRadius,zeroHeight],
										[vertPos.x,vertPos.y-searchRadius,zeroHeight],
										[vertPos.x+searchRadius,vertPos.y,zeroHeight],
										[vertPos.x-searchRadius,vertPos.y,zeroHeight])
				rayArrayStart=#([vertPos.x+searchRadius,vertPos.y+searchRadius,vertPos.z],
										[vertPos.x-searchRadius,vertPos.y+searchRadius,vertPos.z],
										[vertPos.x+searchRadius,vertPos.y-searchRadius,vertPos.z],
										[vertPos.x-searchRadius,vertPos.y-searchRadius,vertPos.z],
										[vertPos.x,vertPos.y+searchRadius,vertPos.z],
										[vertPos.x,vertPos.y-searchRadius,vertPos.z],
										[vertPos.x+searchRadius,vertPos.y,vertPos.z],
										[vertPos.x-searchRadius,vertPos.y,vertPos.z])
				for r=1 to rayArrayEnd.count do
				(
						--尝试射线簇
					rayTarget = normalize (rayArrayEnd[r] - rayArrayStart[r])
					theHitsCount=rm.intersectRay rayArrayStart[r] rayTarget doubleSidedHitTest
					if theHitsCount>0 do 
					(
						dist=rm.getHitDist (rm.getClosestHit())
						hitPos=rayArrayStart[r]+(rayTarget*dist)
						append searchRays hitPos
					)
					
					if searchRays.count==0 do
					(
							--如果射线簇失败，尝试使用慢速方法的射线簇（有时会出现孔洞问题.max）
						shootRay = ray rayArrayStart[r] rayTarget
						hit=intersectRay target_obj shootRay
						if hit!=undefined do 
						(
							append searchRays hit.pos
						)
					)
					
				)
				numberOfRayIterations+=1
				
				if searchRadius>=maxSearchRadius then keepSearching=false
				else searchRadius*=stepSize
			)
			while searchRays.count==0 and keepSearching
			--print searchRadius
			if searchRays.count>0 then
			(
				local averageZ=0.0
				for r in searchRays do
				(
					averageZ+=r.z
					--if i==1580 do point pos:r drawontop:on constantscreensize:on centermarker:on wirecolor:green
				)
				averageZ=averageZ/searchRays.count
				setVert obj i [vertPos0.x,vertPos0.y,averageZ]
			)
			else
			(
				--setVert obj i vertPos0
				append leftover_verts i
			)
		)
		else 
		(
			if deleteMissedVerts then append vertsToDelete i
			else setVert obj i [vertPos0.x,vertPos0.y,zeroHeight]	--将顶点设置为零边界框高度
		)
	)
	
	--rm.PrintStats() 
	if mlptSettings.debug_mode do format "射线搜索迭代次数: % 修复顶点数: %\n" numberOfRayIterations leftover_verts.numberset
	rm.free()

		--通过分析边缘上的相邻顶点，使用它们的平均高度来修复剩余顶点
	if fixLeftoverVerts and leftover_verts.numberset>0 do
	(
		for i in leftover_verts do
		(
			local edgesToProcess=meshopGetEdgesUsingVert obj i
			if borderEdges!=undefined do edgesToProcess=borderEdges*edgesToProcess
			local neighboringVerts=meshopGetVertsUsingEdge obj edgesToProcess
			neighboringVerts-=leftover_verts --dont use leftover vertices for average values
			
			local averageVertexHeight=0.0
			for i in neighboringVerts do
			(
				local thisVert=getVert obj i
				averageVertexHeight+=thisVert.z
			)
			averageVertexHeight=averageVertexHeight/neighboringVerts.numberset
			badVertex=getVert obj i
			local badVertexNewPos=[badVertex.x,badVertex.y,averageVertexHeight]
			setVert obj i badVertexNewPos
		)
	)
	
	convertToPoly obj
	if deleteMissedVerts do 
	(
		polyOpDeleteVerts obj vertsToDelete
	)
)
/*
	--遗留代码，不再使用
function zWrapUsingSkinWrapMorpher resultPlane obj snapshotFlat centerpos=
(
	local mod_morpher=morpher Autoload_of_targets:1
	addModifier obj mod_morpher
	WM3_MC_BuildFromNode mod_morpher 1 snapshotFlat
	WM3_MC_SetValue mod_morpher 1 100.0

	if mlptSettings.debug_mode do local redrawTime=(timeStamp() - startTime) / 1000.0
	if mlptSettings.debug_mode do format "变形:          %\n" redrawTime
	
	if thisProgressBar!=undefined do thisProgressBar.value=50

	resultPlane.position=centerpos

	local skin_wrap_mod=Skin_Wrap weightAllVerts:true engine:0 falloff:0.001 meshlist:#(obj)
	addModifier resultPlane skin_wrap_mod
	classOf resultPlane
	WM3_MC_SetValue mod_morpher 1 0.0
	if thisProgressBar!=undefined do thisProgressBar.value=75

)
*/
	--测试对象是样条线还是网格
fn getObjectType obj=
(
	if (isShapeObject obj) then #spline
	else #mesh
)
	--返回修改器堆栈中给定位置的对象类
	--慢！
fn getObjectTypeInModifierStack obj stackposition:#baseobject= 
(
	local returnObjectType
	if stackposition==#baseobject then
	(
		case (superclassof obj.baseobject) of
		(
			GeometryClass:returnObjectType=#mesh
			shape:returnObjectType=#spline
		)
	)
	else
	(
		local oldPanel = getCommandPanelTaskMode() --记住旧的命令面板选项卡
		stopRedraw()
		setCommandPanelTaskMode mode:#modify
		local oldStackPosition=modPanel.getCurrentObject()
		if stackposition==#baseobject then modPanel.setCurrentObject obj.baseobject 
		else modPanel.setCurrentObject obj.modifiers[stackposition]
		showEndResult =off
		returnObjectType=getObjectType obj
		showEndResult =on

		modPanel.setCurrentObject oldStackPosition
		
		setCommandPanelTaskMode oldPanel --切换回之前的命令面板选项卡
		resumeRedraw()
	)
	--print returnObjectType
	returnObjectType
)
fn autoDetectSplineMeshingMode obj=
(
	local thisObjDimensions=getBBox obj
	if ((classOf  obj == Splineshape or classOf  obj ==line) and (thisObjDimensions.z>0.0001)) then	2 --轮廓线
	else 1 --填充模式
)
fn getBaseObjectType obj randomAppDataID:randomAppDataID=
(
	local thisModStack=obj.modifiers
	local returnObjectType
	if thisModStack.count>0 then
	(
		local thisStackPosition=1
		
		keepLooking=true
		while thisStackPosition<=thisModStack.count and keepLooking do
		(
			local thisMod=thisModStack[thisStackPosition]
			local thisModClass=classOf thisMod
			if thisModClass==Relax or thisModClass==TurboSmooth or thisModClass==Edit_Poly then
			(
				if (getAppData thisMod randomAppDataID)==undefined then keepLooking=false
				else thisStackPosition+=1
			)
			else keepLooking=false
		)
		if thisStackPosition==1 then returnObjectType=getObjectType obj
		else if thisStackPosition>thisModStack.count then returnObjectType=getObjectTypeInModifierStack obj stackposition:#baseobject
		else returnObjectType=getObjectTypeInModifierStack obj stackposition:thisStackPosition
	)
	else returnObjectType=getObjectType obj
	returnObjectType
)

local mod_vertex_weld=vertex_weld threshold:0.001
fn addVertexWeldMod obj collapseToPoly:false=
(
	addModifier obj mod_vertex_weld
	if collapseToPoly do convertToPoly obj
)
--将Relax修改器的控制器链接到微调器
fn linkRelaxMod obj spinner_relax spinner_iterations=
(
	local thisMod
	for i in obj.modifiers where classOf i==Relax and getAppData i randomAppDataID=="1" do
	(
		thisMod=i
	)
	if thisMod!=undefined do
	(
		spinner_relax.controller=thisMod.relax_value.controller
		spinner_iterations.controller=thisMod.iterations.controller
	)
)
--将TurboSmooth修改器的控制器链接到微调器
fn linkTurboSmoothMod obj spinner_iterations=
(
	local thisMod
	for i in obj.modifiers where classOf i==TurboSmooth and getAppData i randomAppDataID=="1" do
	(
		thisMod=i
	)
	if thisMod!=undefined do
	(
		spinner_iterations.controller=thisMod.iterations.controller
	)
)
fn addRelaxMod obj val iterations tagWithAppData:false=
(
	local mod_relax=relax relax_value:val iterations:iterations Keep_Boundary_Pts_Fixed:1 name:"Populate:Relax"
	addModifier obj mod_relax
	if tagWithAppData do setAppData mod_relax randomAppDataID "1" --标记修改器
	mod_relax.relax_value.controller = bezier_float() --为链接到地形填充UI分配控制器
	mod_relax.iterations.controller = bezier_float()
)
fn addTurboSmoothMod obj iterations isolinedisplay tagWithAppData:false=
(
	local mod_turboSmooth=turboSmooth iterations:iterations isolineDisplay:isolinedisplay name:"Populate:TurboSmooth"
	addModifier obj mod_turboSmooth
	if tagWithAppData do setAppData mod_turboSmooth randomAppDataID "1" --标记修改器
	mod_turboSmooth.iterations.controller = bezier_float()  --为链接到地形填充UI分配控制器
)
fn deleteRelaxTurboSmoothMods obj randomAppDataID:randomAppDataID=
(
	local modifiersToDelete=#()
	local thisModStack=obj.modifiers
	for m in thisModStack do
	(
		local thisModClass=classOf m
		if thisModClass==Relax or thisModClass==TurboSmooth do
		(
			if (getAppData m randomAppDataID)!=undefined do append modifiersToDelete m
		)
	)
	for m in modifiersToDelete do deleteModifier obj m
)

fn startTerrainCreation originalObj subdivs_x:10 subdivs_y:10 optimizeBorderEdges:true trimToGrid:false shapeMode:#terrainCompound normalizeLength:30 thisProgressBar:false updateModifier:undefined tagWithAppData:false trimShape:undefined trimInvert:false=
	(

	if mlptSettings.debug_mode do local redrawTime=(timeStamp() - startTime) / 1000.0
	if mlptSettings.debug_mode do format "Start:          %\n" redrawTime

	local obj
	if updateModifier!=undefined then updateModifier.enabled=false
	
		--创建布尔实体
		--如果结果不是一个良好的封闭网格，则尝试第二次，不翻转法线
	local booleanShapeOK=false
	local trimShapeMesh=undefined
	local count=0
	while booleanShapeOK==false and count<=2 do
		(
		count+=1
			
		if count==2 do
		(
			delete obj
			delete snapshotFlat
			delete snapshotFlatBoolean
		)			
		
		if isShapeObject originalObj then local mode=#shape else mode=#mesh
		
		if mode==#shape then
		(
			obj=prepareSplineForTerrain originalObj shapeMode:shapeMode normalizeLength:normalizeLength
		)
		else --mesh
		(
			obj=snapshot originalObj name:"mlpt_tempmesh1"
		)

		resetXForm obj --第1步
		CenterPivot obj --第2步
		--convertToMesh obj
		resetXForm obj --第3步
		convertToMesh obj
		
		local centerpos=obj.pos
		local bbox=nodeLocalBoundingBox obj
		local size=(bbox[2]-bbox[1])
		local w=size[1]
		local l=size[2]
		local h=size[3]
		local zmin=obj.min.z
		local zmax=obj.max.z
		
		if mode==#mesh and count==1 do collectFlippedMeshFaces obj flipOnlyIfAllFacesPointingDownwards:true deleteFlippedFaces:true --删除向下指向的面。如果所有面都向下指向则翻转，不删除
		
			--创建边界的布尔实体 
		snapshotFlat=snapshot obj name:"mlpt_tempmesh2"
		if h>0.001 do flattenMesh snapshotFlat
		snapshotFlatBoolean=snapshot snapshotFlat name:"mlpt_tempmesh3"
		
		snapshotFlatBoolean=createBooleanSolid snapshotFlatBoolean h --为布尔相交创建实体网格

		thisOpenEdges=meshOp.getOpenEdges snapshotFlatBoolean	--获取开放边缘以查看样条线挤出是否成功。0=完美结果，实体挤出，全部封口。
		booleanShapeOK=thisOpenEdges.numberset==0 --检查网格是否封闭 = 无开放边缘
		
		if booleanShapeOK and trimShape!=undefined do
		(
			trimShape=copy trimShape name:"mlpt_temptrimshape"
			trimShape.pos.z=obj.pos.z
			trimShapeMesh=createBooleanSolid trimShape h mode:#splineextrude
		)	
		
		if mlptSettings.debug_mode do
		(
			if count==1 and booleanShapeOK do format "Trimmed using Method 1\n"
			if count==2 and booleanShapeOK do format "Trimmed using Method 2\n"
			if count==2 and not booleanShapeOK do format "Trimmed using Method 2, open edges found\n"
		)
	)
	

	
		--创建平面与布尔实体相交
	resultPlane=plane pos:centerpos width:w length:l lengthsegs:subdivs_y widthsegs:subdivs_x name:"mlpt_tempplane"
	
	--copy resultPlane name:"TEST"
	--copy snapshotFlatBoolean name:"TEST"
	
	if not trimToGrid then
	(
		booleanIntersect resultPlane snapshotFlatBoolean engine:#proboolean
		if trimShapeMesh!=undefined do booleanSubstract resultPlane trimShapeMesh _invert:trimInvert
		convertToMesh resultPlane
			
		if resultPlane.numfaces<1 then --检查布尔运算是否失败，尝试使用其他布尔引擎
		(
			--不够优雅！如果proboolean失败则重新执行所有操作
			if mlptSettings.debug_mode do format "Boolean method 2\n"

			delete resultPlane
			snapshotFlatBoolean=snapshot snapshotFlat name:"mlpt_tempmesh4"
			snapshotFlatBoolean=createBooleanSolid snapshotFlatBoolean h --为布尔相交创建实体网格
			resultPlane=plane pos:centerpos width:w length:l lengthsegs:subdivs_y widthsegs:subdivs_x name:"mlpt_tempplane"
			booleanIntersect resultPlane snapshotFlatBoolean engine:#boolean
			convertToMesh resultPlane
		)
		else if mlptSettings.debug_mode do format "Boolean method 1\n"

		if mlptSettings.debug_mode do local redrawTime=(timeStamp() - startTime) / 1000.0
		if mlptSettings.debug_mode do format "Boolean:        %\n" redrawTime

		meshop.deleteIsoVerts resultPlane
	)
	else convertToMesh resultPlane
	pushPrompt "Trimming complete"
	
		--如果基础对象是平的则无需包裹
	if h>0.001 or trimToGrid then
	(
		if thisProgressBar!=undefined do thisProgressBar.value=30

		if mlptSettings.debug_mode do format "Wrap h=%\n" h

			--返回多边形
		resultPlane.pos.z=bbox[2].z
		zWrapMesh resultPlane obj bbox:bbox fixLeftoverVerts:(not trimToGrid) keepShootingIfRayFailed:(not trimToGrid) deleteMissedVerts:trimToGrid --snapToVertsPositions:originalObjBorderEdgeVertsPositions
		
		if thisProgressBar!=undefined do thisProgressBar.value=60

		--zWrapUsingSkinWrapMorpher resultPlane obj snapshotFlat centerpos
	)
	
	if mlptSettings.debug_mode do local redrawTime=(timeStamp() - startTime) / 1000.0
	if mlptSettings.debug_mode do format "Wrap:           %\n" redrawTime

	addVertexWeldMod resultPlane collapseToPoly:true
	
	CenterPivot resultPlane
	
		--存储顶点以便稍后在编辑多边形修改器中移除，因为操作需要访问修改面板
	if optimizeBorderEdges do local verticesToRemove=collectOpenEdgeVertices resultPlane deleteVerts:false

	if mlptSettings.debug_mode do local redrawTime=(timeStamp() - startTime) / 1000.0
	if mlptSettings.debug_mode do format "Verts collect:  %\n" redrawTime

	if thisProgressBar!=undefined do thisProgressBar.value=90

		--检查结果多边形是否有面/布尔运算是否成功
	local returnValue=#ok
	if resultPlane.numfaces>1 then createAndAttachToEditPolyMod originalObj resultPlane updateModifier:updateModifier tagWithAppData:tagWithAppData
	else 
		(
			delete resultPlane
			select originalObj
			returnValue=#emptyResult
		)
		
	if mlptSettings.debug_mode do local redrawTime=(timeStamp() - startTime) / 1000.0
	if mlptSettings.debug_mode do format "Create Mod:     %\n" redrawTime
		
 	if not trimToGrid then
	(
			--优化边界边缘，移除收集的顶点
		if optimizeBorderEdges and verticesToRemove!=undefined and verticesToRemove.count>0 do removePolyVerts originalObj verticesToRemove
		if mlptSettings.debug_mode do local redrawTime=(timeStamp() - startTime) / 1000.0
		if mlptSettings.debug_mode do format "Optimize:       %\n" redrawTime
	)
	
	--delete obj
	--delete snapshotFlat
	delete $mlpt_temp*
	nodeInvalRect originalObj	--flag object to redraw
	popPrompt()
	returnValue
)
------------------------------------------------------
-- 点云生成函数
------------------------------------------------------
	--为循环中单元格的桶渲染样式查找创建偏移坐标
growVoxelCellArray=#([0,0],[-1,0],[-1,1],[0,1],[1,1],[1,0],[1,-1],[0,-1],[-1,-1],\ --1 -- 8
	[-2,0],[-2,1],[-2,2],[-1,2],[0,2],[1,2],[2,2],[2,1],[2,0],[2,-1],[2,-2],[1,-2],[0,-2],[-1,-2],[-2,-2],[-2,-1] ,\ --16
	[-3,0],[-3,1],[-3,2],[-3,3],[-2,3],[-1,3],[0,3],[1,3],[2,3],[3,3],[3,2],[3,1],[3,0],[3,-1],[3,-2],[3,-3],[2,-3],[1,-3],[0,-3],[-1,-3],[-2,-3],[-3,-3],[-3,-2],[-3,-1],\ --24
	[-4,0],[-4,1],[-4,2],[-4,3],[-4,4],[-3,4],[-2,4],[-1,4],[0,4],[1,4],[2,4],[3,4],[4,4],[4,3],[4,2],[4,1],[4,0],[4,-1],[4,-2],[4,-3],[4,-4],[3,-4],[2,-4],[1,-4],[0,-4],[-1,-4],[-2,-4],[-3,-4],[-4,-4],[-4,-3],[-4,-2],[-4,-1],\ --32
	[-5,0],[-5,1],[-5,2],[-5,3],[-5,4],[-5,5],[-4,5],[-3,5],[-2,5],[-1,5],[0,5],[1,5],[2,5],[3,5],[4,5],[5,5],[5,4],[5,3],[5,2],[5,1],[5,0],[5,-1],[5,-2],[5,-3],[5,-4],[5,-5],[4,-5],[3,-5],[2,-5],[1,-5],[0,-5],[-1,-5],[-2,-5],[-3,-5],[-4,-5],[-5,-5],[-5,-4],[-5,-3],[-5,-2],[-5,-1], \ --40
	[-6,0],[-6,1],[-6,2],[-6,3],[-6,4],[-6,5],[-6,6],[-5,6],[-4,6],[-3,6],[-2,6],[-1,6],[0,6],[1,6],[2,6],[3,6],[4,6],[5,6],[6,6],[6,5],[6,4],[6,3],[6,2],[6,1],[6,0],[6,-1],[6,-2],[6,-3],[6,-4],[6,-5],[6,-6],[5,-6],[4,-6],[3,-6],[2,-6],[1,-6],[0,-6],[-1,-6],[-2,-6],[-3,-6],[-4,-6],[-5,-6],[-6,-6],[-6,-5],[-6,-4],[-6,-3],[-6,-2],[-6,-1], \ --48
	[-7,0],[-7,1],[-7,2],[-7,3],[-7,4],[-7,5],[-7,6],[-7,7],[-6,7],[-5,7],[-4,7],[-3,7],[-2,7],[-1,7],[0,7],[1,7],[2,7],[3,7],[4,7],[5,7],[6,7],[7,7],[7,6],[7,5],[7,4],[7,3],[7,2],[7,1],[7,0],[7,-1],[7,-2],[7,-3],[7,-4],[7,-5],[7,-6],[7,-7],[6,-7],[5,-7],[4,-7],[3,-7],[2,-7],[1,-7],[0,-7],[-1,-7],[-2,-7],[-3,-7],[-4,-7],[-5,-7],[-6,-7],[-7,-7],[-7,-6],[-7,-5],[-7,-4],[-7,-3],[-7,-2],[-7,-1], \ --56
	[-8,0],[-8,1],[-8,2],[-8,3],[-8,4],[-8,5],[-8,6],[-8,7],[-8,8],[-7,8],[-6,8],[-5,8],[-4,8],[-3,8],[-2,8],[-1,8],[0,8],[1,8],[2,8],[3,8],[4,8],[5,8],[6,8],[7,8],[8,8],[8,7],[8,6],[8,5],[8,4],[8,3],[8,2],[8,1],[8,0],[8,-1],[8,-2],[8,-3],[8,-4],[8,-5],[8,-6],[8,-7],[8,-8],[7,-8],[6,-8],[5,-8],[4,-8],[3,-8],[2,-8],[1,-8],[0,-8],[-1,-8],[-2,-8],[-3,-8],[-4,-8],[-5,-8],[-6,-8],[-7,-8],[-8,-8],[-8,-7],[-8,-6],[-8,-5],[-8,-4],[-8,-3],[-8,-2],[-8,-1] \ --64
)
growVoxelIterationsCellCount=#([1,1],[2,9],[10,25],[26,49],[50,81],[82,121],[122,169],[170,225],[226,289])
	--返回给定网格的点位置数组
fn generatePointsFromMeshVerts obj=
(
	local verts = obj.verts as bitarray
	for i in verts collect GetVert obj i
)
	--返回给定样条线的点位置数组
fn generatePointsFromSpline pointCloud=
(
	--将点云中的所有点作为带位置的数组收集
	pointsPositions=#()
	for s = 1 to (numSplines pointCloud) do
	(
		for k = 1 to (numKnots pointCloud s) do
		(
			append pointsPositions (getKnotPoint pointCloud s k)
		)
	)
	pointsPositions
)
	--体素网格初始化
	--返回给定点云和体素网格大小的地址
fn initVoxelData points cellSize: pointsPositions: origin: =
(
	data=#()
	for i in points do
	(
		thisPoint=pointsPositions[i]
		pos=[thisPoint.x-origin.x,thisPoint.y-origin.y]/cellSize+0.9999
		if pos.x<1 do pos.x=1
		if pos.y<1 do pos.y=1
		if data[pos.y] == undefined then
		(
			data[pos.y] = #()
			data[pos.y][pos.x] = #{i}
		)
		else if data[pos.y][pos.x] == undefined then data[pos.y][pos.x] = #{i}
		else append data[pos.y][pos.x] i
	)
	data
)
	--返回给定搜索位置的体素单元格中的点
fn findVoxelpointsPositions searchPos voxelAdresses min_grow_iterations:6 =
(
	local allVoxelHits=#{}
	local keepsearching_cycle=1
	local finishround=false
	local thisVoxelHits=#{}
	local cycle=1
	do
	(
		for i=growVoxelIterationsCellCount[cycle][1] to (growVoxelIterationsCellCount[cycle][2]) do
		(
			local neighborSearch=searchPos+growVoxelCellArray[i]
			if neighborSearch.y<1 do neighborSearch.y=1	--避免负索引...不要在数组边界外查找
			if neighborSearch.x<1 do neighborSearch.x=1
			
			thisVoxelHitsRow=voxelAdresses[neighborSearch.y]
			if thisVoxelHitsRow!=undefined do 
			(
				thisVoxelHits=thisVoxelHitsRow[neighborSearch.x]
				if thisVoxelHits==undefined do thisVoxelHits=#{}
			)
			if not thisVoxelHits.isEmpty then --当找到点时
			(
				join allVoxelHits thisVoxelHits --将点添加到数组
				keepsearching_cycle+=1 
				if keepsearching_cycle>=min_grow_iterations do finishround=true --再搜索一轮以避免块对齐错误
			)
		)
		cycle+=1
		if cycle>growVoxelIterationsCellCount.count do finishround=true
	)
	while not finishround 
	allVoxelHits
)

------------------------------------------------------
-- 点云生成函数结束
------------------------------------------------------

fn startPointCloudTerrainCreation originalObj subdivs_x:10 subdivs_y:10 normalizeLength: thisProgressBar:false tagWithAppData:false trimShape:undefined=
(
	if mlptSettings.debug_mode do local redrawTime=(timeStamp() - startTime) / 1000.0
	if mlptSettings.debug_mode do format "Start:          %\n" redrawTime

		--检查对象是否为样条线
	if isShapeObject originalObj then
	(
		obj=copy originalObj name:"mlpt_tempspl1"
		local mod_normalizeSpline=Normalize_Spl length:normalizeLength
		addModifier obj mod_normalizeSpline
		convertToSplineShape obj
		local pointsPositions=generatePointsFromSpline obj
	)
		--对象是网格
	else 
	(
		obj=snapshot originalObj name:"mlpt_tempmesh1"
		local pointsPositions=generatePointsFromMeshVerts obj
	)
	
	local points=#{1..pointsPositions.count}
	
	resetXForm obj --第1步
	CenterPivot obj --第2步
	--convertToMesh obj
	resetXForm obj --第3步
	--convertToMesh obj --慢！为什么？
	
	local centerpos=obj.pos
	local bbox=nodeLocalBoundingBox obj
	local size=(bbox[2]-bbox[1])
	local w=size[1]
	local l=size[2]
	local h=size[3]
	local zmin=obj.min.z
	local zmax=obj.max.z

		--创建平面与布尔实体相交
	local resultPlane=plane pos:centerpos width:w length:l lengthsegs:subdivs_y widthsegs:subdivs_x name:"mlpt_tempmesh_plane"
	convertToPoly resultPlane
	--从边界框清理
	
	local verts = resultplane.verts as bitarray
	local vertsPos = for i in verts collect polyOpGetVert resultplane i
	--copy resultPlane name:"TEST"
	--copy snapshotFlatBoolean name:"TEST"

		--准备体素网格
	--local cellSize=[(w/subdivs_x),(l/subdivs_y)]*10 --体素单元格大小=网格单元格大小=最精细分辨率
	local cellSize=[w,l]/64
	local origin=[resultplane.min.x,resultplane.min.y]
	local voxelAdresses=initVoxelData points cellSize:cellSize pointsPositions:pointsPositions origin:origin

	--thisProgressBar=undefined
		--初始化进度条
	if thisProgressBar!=undefined do
		(
		local loopcount=verts.numberset
		local percentage=loopcount/100
		local current_progress=0
		)
	
		--开始循环顶点
	local newVertsPos=#()
	local notfound=0
	for v in verts do 
	(
			--更新进度条
		if thisProgressBar!=undefined do
		(
			current_progress+=1
			if (mod current_progress percentage == 0) do
			(
				thisProgressBar.value=ceil current_progress/percentage
			)
		)

		
		local thisVertPos = vertsPos[v]
		local vert2dPos=[thisVertPos.x,thisVertPos.y]
		
		local searchPos=[thisVertPos.x-origin.x,thisVertPos.y-origin.y]/cellSize+0.9999

		local pointsToMeasure=findVoxelpointsPositions searchPos voxelAdresses --min_grow_iterations:3
		
			--这不应该发生...即使在桶渲染样式单元格增长后也没有找到点...使用所有点进行测量
		if pointsToMeasure.isEmpty do 
		(
			notfound+=1
			pointsToMeasure=points
		)
		
		local smallestDistance=100000000
		local nearestPoint
		for m in pointsToMeasure do 
		(
			local thisDistance=distance vert2dPos [pointsPositions[m].x,pointsPositions[m].y]
			if thisDistance<smallestDistance do 
			(
				smallestDistance=thisDistance
				nearestPoint=pointsPositions[m]
			)
		)
		append newVertsPos [thisVertPos.x,thisVertPos.y,nearestPoint.z]
	)

		polyOpSetVert resultplane verts newVertsPos
		if mlptSettings.debug_mode and notfound>0 do format "点云顶点慢速查找: %\n" notfound
	/*
		if resultPlane.numfaces>1 then createAndAttachToEditPolyMod originalObj resultPlane updateModifier:updateModifier tagWithAppData:tagWithAppData
		else 
			(
				delete resultPlane
				select originalObj
				returnValue=#emptyResult
			)
		
	*/
	resultPlane.name=originalObj.name+":Terrain"

	
	
	delete $mlpt_temp*
	returnValue
)
fn doTerrain=
(
	updateAllRolloutSettings() --刷新以更新方形约束的细分

	-- 检查是否选择了有效对象
	local thisObj=getCurrentObject()
	if thisObj == undefined then
	(
		-- 显示弹窗提醒用户选择模型
		messageBox "请先选择一个几何体或样条线对象再执行地形生成操作！" title:"未选择对象" beep:true
		return undefined
	)

	if mlptSettings.debug_mode do 
	(
		heapBegin=heapfree
		startTime = timeStamp()
		local max_version=(maxVersion())[1] / 1000.0
		
		format "============================================================\n"
		format "Populate:Terrain - Processing started at %\n" localTime
		format "Version: % - 3ds max: %\n" populate_version max_version
	)
	
	mlpt_dialog_populate.prg_progress.value=10
	mlpt_dialog_populate.prg_progress.visible=true

		--关闭转义启用，使用自己的进度条取消安全中断
	local oldEscapeEnable = escapeEnable 
	escapeEnable = false
	setWaitCursor()
	redrawviews()	--防止崩溃？
	stopRedrawPanel()
	
		--删除地形填充生成的松弛和涡轮平滑修改器
	deleteRelaxTurboSmoothMods thisObj
	
		--检查是否已存在地形填充修改器以进行更新
	local thisObjFirstModifier=thisObj.modifiers[1]
	local hasAppdata=undefined
	if (thisObjFirstModifier!=undefined) do hasAppdata=getAppData thisObjFirstModifier randomAppDataID
	local modifierToUpdate=
	(
		if hasAppdata!=undefined then --禁用之前的地形填充修改器，以便能够检测基础对象
		(
			if mlptSettings.debug_mode do format "正在更新现有修改器...\n"
			thisObjFirstModifier.enabled=false
			thisObjFirstModifier
		)
		else undefined
	)
	
		--检查基础对象是否为样条线
	if isShapeObject thisObj then
	(
		if mlptSettings.debug_mode do format "基础对象是样条线\n"
		local thisMeshingMethod
		
			--自动检测最佳网格化方法
		if mlptSettings.automethod then 
		(
			case (autoDetectSplineMeshingMode thisObj) of
			(
				1:
				(
					thisMeshingMethod=#fill
					if mlptSettings.debug_mode do format "样条线网格化: 自动 - 使用填充模式\n"
				)
				2:
				(
					thisMeshingMethod=#terrainCompound
					if mlptSettings.debug_mode do format "样条线网格化: 自动 - 使用轮廓线模式\n"
				)
			)
		)
		else case mlptSettings.meshingmethod of
		(
			1: thisMeshingMethod=#fill
			2: thisMeshingMethod=#terrainCompound
			3: thisMeshingMethod=#pointCloud
		)
		
		if thisMeshingMethod==#terrainCompound or thisMeshingMethod==#pointCloud do
		(
			local thisGridEdgeLength=(if mlptSettings.size_x <= mlptSettings.size_y then mlptSettings.size_x else mlptSettings.size_y)
			local thisNormalizeLength=thisGridEdgeLength
			if mlptSettings.debug_mode do format "样条线标准化长度: %\n" (units.formatValue thisNormalizeLength)
		)
	)
	else --网格
	(
		if mlptSettings.debug_mode do format "基础对象是网格\n"	
		
		case mlptSettings.meshingmethod of
		(
			1: thisMeshingMethod=#retopoMesh
			2: thisMeshingMethod=#pointCloud
		)
	)
	
	local optimizeBorderEdges=(mlptSettings.bordermode==1)
	local trimToGrid=(mlptSettings.bordermode==3)
	
	local trimShape=undefined
	if mlptSettings.cookie_cut do
	(
		trimShape=getNodeFromHandle mlptSettings.cookie_cut_nodehandle
	)
	
	try(mlpt_dialog_populate.lbl_status.text="已选择: "+mlpt_currentObject.name+"\n正在处理..."); catch();
	if isValidNode thisObj do 
	(
		if thisMeshingMethod==#pointCloud then mlpt_returnValue=startPointCloudTerrainCreation thisObj subdivs_x:mlptSettings.subdivs_x subdivs_y:mlptSettings.subdivs_y normalizeLength:thisNormalizeLength thisProgressBar:mlpt_dialog_populate.prg_progress tagWithAppData:true trimShape:trimShape
		else mlpt_returnValue=startTerrainCreation thisObj subdivs_x:mlptSettings.subdivs_x subdivs_y:mlptSettings.subdivs_y optimizeBorderEdges:optimizeBorderEdges trimToGrid:trimToGrid shapeMode:thisMeshingMethod normalizeLength:thisNormalizeLength thisProgressBar:mlpt_dialog_populate.prg_progress updateModifier:modifierToUpdate tagWithAppData:true trimShape:trimShape trimInvert:mlptSettings.cookie_invert
	)
	if mlptSettings.relax_on do addRelaxMod thisObj mlptSettings.relax_value mlptSettings.relax_iterations tagWithAppData:true
	if mlptSettings.turbosmooth_on do addTurboSmoothMod thisObj mlptSettings.turbosmooth_iterations mlptSettings.turbosmooth_isolinedisplay tagWithAppData:true

	resumeRedrawPanel()
	setArrowCursor()
		--恢复目标对象结束
	escapeEnable = oldEscapeEnable
	mlpt_dialog_populate.prg_progress.visible=false
	
	storeSettingsIntoModifier thisObj
	
	if mlptSettings.debug_mode do 
	(
		redrawTime=(timeStamp() - startTime) / 1000.0
		heapEnd=(heapBegin-heapFree) as float
		format "总计算时间: % 秒\n泄漏: %\n" redrawTime ((heapEnd / 1000) as integer)
		
		format "Processing ended at                      %\n" localTime
		format "============================================================\n"
		gc lite:true
	)
	
)
--------------------------------------------
-- 地形创建函数结束
--------------------------------------------

fn objectSelected updateStatusText:true=
(
		--从修改器获取应用数据设置。如果有应用数据则更新对话框设置
	if (mlpt_currentObject.modifiers[1]!=undefined) do local thisObjectSettings=getAppData mlpt_currentObject.modifiers[1] randomAppDataSettings
	if thisObjectSettings!=undefined do
	(
		thisObjectSettings=try(execute thisObjectSettings)
		catch(thisObjectSettings=undefined)
		if thisObjectSettings!=undefined do 
		(
				--仅在应用数据来自匹配脚本版本时更新
			if isProperty thisObjectSettings "version" and thisObjectSettings.version==populate_version do 
			(
				mlptSettings=thisObjectSettings
			)
		)
	)
	
		--对象是样条线
	if (getBaseObjectType mlpt_currentObject)==#spline then 
	(
		--mlpt_ro_common.drp_meshingmethod.items=#("Fill with Island Detection", "Contour Lines", "Vertex Point Cloud") --为测试版禁用
		mlpt_ro_common.drp_meshingmethod.items=#("填充并检测孤岛", "等高线")
		mlpt_ro_common.drp_meshingmethod.selection=(if mlptSettings.meshingmethod>0 and mlptSettings.meshingmethod<=mlpt_ro_common.drp_meshingmethod.items.count then mlptSettings.meshingmethod else 1)
		mode_string="模式: 样条线网格化"
		
		if mlpt_ro_common.chk_automethod.checked then 
		(
			mlptSettings.meshingmethod=mlpt_ro_common.drp_meshingmethod.selection=autoDetectSplineMeshingMode mlpt_currentObject
		)
	)
	else --对象是网格
	(
		--mlpt_ro_common.drp_meshingmethod.items=#("Surface Retopology", "Vertex Point Cloud")
		mlpt_ro_common.drp_meshingmethod.items=#("表面重拓扑")
		mlpt_ro_common.drp_meshingmethod.selection=(if mlptSettings.meshingmethod>0 and mlptSettings.meshingmethod<=mlpt_ro_common.drp_meshingmethod.items.count then mlptSettings.meshingmethod else 1)
		mode_string="模式: 表面重拓扑"
	)
	
	try(mlpt_dialog_populate.lbl_status.text="已选择: "+mlpt_currentObject.name+"\n"+mode_string+"\n准备处理。"); catch();
	try(mlpt_dialog_populate.btn_process.enabled=true); catch();

	
	--linkRelaxMod mlpt_currentObject mlpt_ro_postprocessing.spn_relax_value mlpt_ro_postprocessing.spn_relax_iterations
	--linkTurboSmoothMod mlpt_currentObject  mlpt_ro_postprocessing.spn_turbosmooth_iterations
)

-----------------------------------
-- 卷展栏开始
-----------------------------------
rollout mlpt_ro_common "表面"
(
	group "网格"
	(
		radiobuttons rdo_subdivs_type "模式" labels:#("细分", "尺寸", "百分比") default:mlptSettings.subdiv_mode align:#right offset:[-10,-3]
		spinner spn_subdivs_X "X:" align:#left fieldwidth:90 type:#integer range:[2,1e9,mlptSettings.subdivs_x] tooltip:"" offset:[0,-30]
		spinner spn_subdivs_Y "Y:" align:#left fieldwidth:90 type:#integer range:[2,1e9,mlptSettings.subdivs_y] tooltip:""
		checkbox chk_square "近似正方形" align:#left across:2 checked:mlptSettings.square offset:[0,2] tooltip:"尽可能使用正方形网格细分"
		checkbutton chk_preview "预览网格" offset:[-17,-2] align:#left checked:false tooltip:"在活动视口中显示当前细分设置的预览网格"
		spinner spn_size_X "X:" align:#left fieldwidth:90 type:#worldunits range:[0,1e9,mlptSettings.size_x] tooltip:"" offset:[0,-20] visible:false
		spinner spn_size_Y "Y:" align:#left fieldwidth:90 type:#worldunits range:[0,1e9,mlptSettings.size_y] tooltip:"" offset:[0,-20] visible:false
		spinner spn_percent_X "X:" align:#left fieldwidth:90 type:#float range:[0,100,mlptSettings.percent_x] tooltip:"" offset:[0,-20] visible:false
		spinner spn_percent_Y "Y:" align:#left fieldwidth:90 type:#float range:[0,100,mlptSettings.percent_y] tooltip:"" offset:[0,-20] visible:false
	)
	group "网格化"
	(
		checkbox chk_automethod "检测最佳方法" across:2 offset:[0,2] align:#left checked:mlptSettings.square tooltip:"自动检测最佳网格化方法"
		dropdownlist drp_meshingmethod "" align:#right width:170 offset:[0,-1] default:mlptSettings.meshingmethod tooltip:"网格化方法"
	)
	groupbox grp1 "边界" pos:[4,156] width:180 height:70
	groupbox grp2 " " pos:[190,156] width:141 height:70
	--radiobuttons rdo_border "Edge Resolution" labels:#("Optimize", "Exact", "Grid") offset:[0,-50] default:mlptSettings.bordermode align:#left tooltip:#("Collapse border edges to grid cell length", "Keep all border vertices of the original geometry", "Coarse trimming to whole quad faces")		
	radiobuttons rdo_border "边缘分辨率" labels:#("优化", "保持原始") offset:[0,-50] default:mlptSettings.bordermode align:#left tooltip:#("将边界边缘折叠到网格单元长度", "保持原始几何体的所有边界顶点")		
	checkbox chk_cookie_cut "修剪" offset:[188,-60]
	pickbutton pck_cookie_cut_spline "选择样条线" autoDisplay:true align:#right width:123 offset:[-1,0] filter:pickFiltSpline
	checkbox chk_cookie_invert "反转" align:#right default:mlptSettings.cookie_invert

	fn updateSettings overwrite:false autoUpdate:false =
	(
		local currentObject=getCurrentObject()
		local currentObjectDimensions=getBBox currentObject
		
		if overwrite then
		(
			mlptSettings.subdiv_mode=rdo_subdivs_type.state
			mlptSettings.subdivs_x=spn_subdivs_X.value
			mlptSettings.subdivs_y=spn_subdivs_Y.value
			mlptSettings.size_x=spn_size_X.value
			mlptSettings.size_y=spn_size_Y.value
			mlptSettings.percent_x=spn_percent_X.value
			mlptSettings.percent_y=spn_percent_Y.value
			mlptSettings.bordermode=rdo_border.state
			mlptSettings.meshingmethod=drp_meshingmethod.selection
			mlptSettings.square=chk_square.state
			mlptSettings.automethod=chk_automethod.state
			mlptSettings.cookie_cut=chk_cookie_cut.state
			mlptSettings.cookie_cut_nodehandle=getHandleFromNode pck_cookie_cut_spline.object
			mlptSettings.cookie_invert=chk_cookie_invert.state

			storeSettingsIntoModifier currentObject
		)
		else
		(
			rdo_subdivs_type.state=mlptSettings.subdiv_mode
			spn_subdivs_X.value=mlptSettings.subdivs_x
			spn_subdivs_Y.value=mlptSettings.subdivs_y
			spn_size_X.value=mlptSettings.size_x
			spn_size_Y.value=mlptSettings.size_y
			spn_percent_X.value=mlptSettings.percent_x
			spn_percent_Y.value=mlptSettings.percent_y
			rdo_border.state=mlptSettings.bordermode
			drp_meshingmethod.selection=mlptSettings.meshingmethod
			chk_square.state=mlptSettings.square
			chk_automethod.state=mlptSettings.automethod
			chk_cookie_cut.state=mlptSettings.cookie_cut
			chk_cookie_invert.state=mlptSettings.cookie_invert
			
			--print mlptSettings.cookie_cut_nodehandle
			local cookie_cut_spline=getNodeFromHandle mlptSettings.cookie_cut_nodehandle
			if (isValidNode currentObject and isValidNode cookie_cut_spline and isShapeObject cookie_cut_spline) then 
			(
				pck_cookie_cut_spline.object=cookie_cut_spline
				pck_cookie_cut_spline.text=cookie_cut_spline.name
			)
			else 
			(
				pck_cookie_cut_spline.object=undefined
				pck_cookie_cut_spline.text="选择样条线"
			)
		)

		case rdo_subdivs_type.state of
		(
			1:
			(
				spn_size_X.visible = spn_size_Y.visible = spn_percent_X.visible = spn_percent_Y.visible = false
				spn_subdivs_X.visible = spn_subdivs_Y.visible = true
				
				if isValidNode currentObject do
				(
					local gridSizeX=currentObjectDimensions.x/mlptSettings.subdivs_x
					local gridSizeY=currentObjectDimensions.y/mlptSettings.subdivs_y
					local percentX=gridSizeX/currentObjectDimensions.x*100.0
					local percentY=gridSizeY/currentObjectDimensions.y*100.0
					spn_size_X.value=mlptSettings.size_x=gridSizeX
					spn_size_Y.value=mlptSettings.size_y=gridSizeY
					spn_percent_X.value=mlptSettings.percent_x=percentX
					spn_percent_Y.value=mlptSettings.percent_y=percentY
				)
			)
			2:
			(
				spn_subdivs_X.visible = spn_subdivs_Y.visible = spn_percent_X.visible = spn_percent_Y.visible = false
				spn_size_X.visible = spn_size_Y.visible = true
				
				if isValidNode currentObject do
				(
					local subdivsX=roundFloat(currentObjectDimensions.x/mlptSettings.size_x) as integer
					local subdivsY=roundFloat(currentObjectDimensions.y/mlptSettings.size_y) as integer
					local percentX=mlptSettings.size_x/currentObjectDimensions.x*100.0
					local percentY=mlptSettings.size_y/currentObjectDimensions.y*100.0
					spn_subdivs_X.value=mlptSettings.subdivs_x=subdivsX
					spn_subdivs_Y.value=mlptSettings.subdivs_y=subdivsY
					spn_percent_X.value=mlptSettings.percent_x=percentX
					spn_percent_Y.value=mlptSettings.percent_y=percentY
				)
			)
			3:
			(
				spn_subdivs_X.visible = spn_subdivs_Y.visible = spn_size_X.visible = spn_size_Y.visible = false
				spn_percent_X.visible = spn_percent_Y.visible = true
				
				if isValidNode currentObject do
				(
					local gridSizeX=mlptSettings.percent_x/100.0*currentObjectDimensions.x
					local gridSizeY=mlptSettings.percent_y/100.0*currentObjectDimensions.y
					local subdivsX=roundFloat(currentObjectDimensions.x/gridSizeX) as integer
					local subdivsY=roundFloat(currentObjectDimensions.y/gridSizeY) as integer
					spn_subdivs_X.value=mlptSettings.subdivs_x=subdivsX
					spn_subdivs_Y.value=mlptSettings.subdivs_y=subdivsY
					spn_size_X.value=mlptSettings.size_x=gridSizeX
					spn_size_Y.value=mlptSettings.size_y=gridSizeY
				)
			)
		)

		--greyed out ui elements
		local controls_enabled=isValidNode currentObject
	
		rdo_subdivs_type.enabled=spn_subdivs_X.enabled=spn_subdivs_Y.enabled=spn_size_X.enabled=spn_size_Y.enabled=spn_percent_X.enabled=spn_percent_Y.enabled=\
		rdo_border.enabled=drp_meshingmethod.enabled=chk_square.enabled=chk_automethod.enabled=chk_cookie_cut.enabled=chk_cookie_invert.enabled=\
		chk_preview.enabled=pck_cookie_cut_spline.enabled=chk_cookie_invert.enabled=controls_enabled
		
		if controls_enabled do
		(
			pck_cookie_cut_spline.enabled=chk_cookie_invert.enabled=chk_cookie_cut.checked
			drp_meshingmethod.enabled=not chk_automethod.checked and drp_meshingmethod.items.count>0

		)
		
		if chk_square.checked then 
		(
			if controls_enabled do spn_subdivs_Y.enabled = spn_size_Y.enabled = spn_percent_Y.enabled = false
			
			if isValidNode currentObject then
			(
				spn_subdivs_Y.indeterminate = spn_size_Y.indeterminate = spn_percent_Y.indeterminate = false --empty spinner false
				
				local gridCountY=currentObjectDimensions.y/mlptSettings.size_x
				gridCountY=roundFloat gridCountY as integer
				mlptSettings.subdivs_y=spn_subdivs_Y.value=gridCountY
			)
			else
			(
				spn_subdivs_Y.indeterminate = spn_size_Y.indeterminate = spn_percent_Y.indeterminate = true --empty spinner
			)
		)
		else
		(
			if controls_enabled do spn_subdivs_Y.enabled = spn_size_Y.enabled = spn_percent_Y.enabled = true
			spn_subdivs_Y.value=spn_subdivs_Y.value --hack to make spinner content visible again after .indeterminate = true
			spn_size_Y.value=spn_size_Y.value --hack
			spn_percent_Y.value=spn_percent_Y.value --hack
		)
		
		if autoUpdate do mlpt_dialog_populate.doAutoUpdate()
		
		mlpt_subdivsX=mlptSettings.subdivs_x
		mlpt_subdivsY=mlptSettings.subdivs_y
				
		if mlpt_ro_common.chk_preview.state do redrawviews()
	)
	
	on rdo_subdivs_type changed a do updateSettings overwrite:true
	on spn_subdivs_X changed a do updateSettings overwrite:true
	on spn_subdivs_X entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on spn_subdivs_Y changed a do updateSettings overwrite:true
	on spn_subdivs_Y entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on spn_size_X changed a do updateSettings overwrite:true
	on spn_size_X entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on spn_size_Y changed a do updateSettings overwrite:true
	on spn_size_Y entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on spn_percent_X changed a do updateSettings overwrite:true
	on spn_percent_X entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on spn_percent_Y changed a do updateSettings overwrite:true
	on spn_percent_Y entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on rdo_border changed a do updateSettings overwrite:true autoUpdate:true
	on drp_meshingmethod selected a do updateSettings overwrite:true autoUpdate:true
	on chk_square changed a do updateSettings overwrite:true autoUpdate:true
	on chk_automethod changed a do 
	(
		updateSettings overwrite:true autoUpdate:true
		if a==true do objectSelected updateStatusText:false
	)
	on chk_preview changed a do mlpt_dialog_populate.dialog_refresh()
	on chk_cookie_cut changed a do updateSettings overwrite:true autoUpdate:true
	on pck_cookie_cut_spline picked a do updateSettings overwrite:true autoUpdate:false
	on chk_cookie_invert changed a do updateSettings overwrite:true autoUpdate:true
		
	on mlpt_ro_common open do
	(
		spn_size_X.pos=spn_percent_X.pos=spn_subdivs_X.pos --position of invisible spinners
		spn_size_Y.pos=spn_percent_Y.pos=spn_subdivs_Y.pos
	)
)
rollout mlpt_ro_postprocessing "后处理"
(
	spinner spn_relax_value "数值:" offset:[-10,20] across:2 align:#right fieldwidth:70 type:#float range:[0,1,mlptSettings.relax_value] tooltip:""
	spinner spn_turbosmooth_iterations "迭代次数:" offset:[0,20] align:#right fieldwidth:70 type:#integer range:[1,10,mlptSettings.turbosmooth_iterations] tooltip:""
	spinner spn_relax_iterations "迭代次数:" offset:[-10,0] across:2 align:#right fieldwidth:70 type:#integer range:[0,1e9,mlptSettings.relax_iterations] tooltip:""
	checkbox chk_turbosmooth_isolinedisplay "等值线显示" align:#right checked:mlptSettings.turbosmooth_isolinedisplay
	groupbox grp1 " " pos:[4,7] width:160 height:65
	groupbox grp2 " " pos:[170,7] width:161 height:65
	checkbox chk_relax_on "松弛" pos:[15,7] checked:mlptSettings.relax_on
	checkbox chk_turbosmooth_on "涡轮平滑" pos:[180,7] checked:mlptSettings.turbosmooth_on 
	
	fn updateSettings overwrite:false autoUpdate:false =
	(
		if overwrite then
		(
			mlptSettings.relax_value=spn_relax_value.value
			mlptSettings.turbosmooth_iterations=spn_turbosmooth_iterations.value
			mlptSettings.relax_iterations=spn_relax_iterations.value
			mlptSettings.turbosmooth_isolinedisplay=chk_turbosmooth_isolinedisplay.state
			mlptSettings.relax_on=chk_relax_on.state
			mlptSettings.turbosmooth_on=chk_turbosmooth_on.state
			
			local currentObject=getCurrentObject()
			storeSettingsIntoModifier currentObject
		)
		else
		(
			spn_relax_value.value=mlptSettings.relax_value
			spn_turbosmooth_iterations.value=mlptSettings.turbosmooth_iterations
			spn_relax_iterations.value=mlptSettings.relax_iterations
			chk_turbosmooth_isolinedisplay.state=mlptSettings.turbosmooth_isolinedisplay
			chk_relax_on.state=mlptSettings.relax_on
			chk_turbosmooth_on.state=mlptSettings.turbosmooth_on
		)
		
			--greyed out ui elements
		local currentObject=getCurrentObject()
		local controls_enabled=isValidNode currentObject
		spn_relax_value.enabled=spn_turbosmooth_iterations.enabled=spn_relax_iterations.enabled=chk_turbosmooth_isolinedisplay.enabled=chk_relax_on.enabled=chk_turbosmooth_on.enabled=controls_enabled
		if controls_enabled then
		(
			spn_relax_value.enabled=chk_relax_on.checked
			spn_relax_iterations.enabled=chk_relax_on.checked
			spn_turbosmooth_iterations.enabled=chk_turbosmooth_on.checked
			chk_turbosmooth_isolinedisplay.enabled=chk_turbosmooth_on.checked
		)

		
		if autoUpdate do mlpt_dialog_populate.doAutoUpdate()
	)
	
	on spn_relax_value entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on spn_turbosmooth_iterations entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on spn_relax_iterations entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
	on chk_turbosmooth_isolinedisplay changed a do updateSettings overwrite:true autoUpdate:true
	on chk_relax_on changed a do updateSettings overwrite:true autoUpdate:true
	on chk_turbosmooth_on changed a do updateSettings overwrite:true autoUpdate:true
)
rollout mlpt_ro_advanced "地形增强"
(
	group "自适应细分"
	(
		checkbox chk_enable_adaptive "启用" across:2 checked:mlptSettings.adaptive_refinement
		spinner spn_vertspercell "每单元顶点数:" align:#right fieldwidth:70 type:#integer range:[1,1e9,mlptSettings.adaptive_refinement_vertspercell] tooltip:""
		spinner spn_iterations "最大迭代次数:" align:#right fieldwidth:70 type:#integer range:[1,16,mlptSettings.adaptive_refinement_maxsubdivs] tooltip:"" 
	)


	fn updateSettings overwrite:false autoUpdate:false =
	(
		if overwrite then
		(
			mlptSettings.adaptive_refinement=chk_enable_adaptive.state
			mlptSettings.adaptive_refinement_vertspercell=spn_vertspercell.value
			mlptSettings.adaptive_refinement_maxsubdivs=spn_iterations.value
		)
		else
		(
			chk_enable_adaptive.state=mlptSettings.adaptive_refinement
			spn_vertspercell.value=mlptSettings.adaptive_refinement_vertspercell
			spn_iterations.value=mlptSettings.adaptive_refinement_maxsubdivs
		)
		if autoUpdate do mlpt_dialog_populate.doAutoUpdate()
	)
	
	on chk_enable_adaptive changed a do updateSettings overwrite:true autoUpdate:true
	on spn_vertspercell changed a do updateSettings overwrite:true autoUpdate:true
	on spn_iterations entered inSpin_arg inCancel_arg do updateSettings overwrite:true autoUpdate:true
		
	on mlpt_ro_advanced open do
	(
		updateSettings()
	)
)

rollout mlpt_ro_debug "选项"
(
	checkbox chk_debug "在MAXScript监听器中打印统计信息" offset:[0,8] checked:mlptSettings.debug_mode
	
	fn updateSettings overwrite:false autoUpdate:false =
	(
		local currentObject=getCurrentObject()
		local currentObjectDimensions=getBBox currentObject
		
		if overwrite then
		(
			mlptSettings.debug_mode=chk_debug.state
		)
		else
		(
			chk_debug.state=mlptSettings.debug_mode
		)
	)
	
	on chk_debug changed a do updateSettings overwrite:true autoUpdate:true

	on mlpt_ro_debug open do
	(
		updateSettings overwrite:true
	)


)
rollout mlpt_ro_modelslicer "模型切割"
(
    group "选择模型"
    (
        pickbutton btn_pickModel "选择要切割的平面模型" width:250 align:#center
        label lbl_selectedModel "未选择模型" align:#center
    )
    group "行数*列数设置"
	(
		spinner spn_rows "行数:" range:[1, 100, mlptSettings.slicer_rows] type:#integer align:#left width:120
        spinner spn_columns "列数:" range:[1, 100, mlptSettings.slicer_columns] type:#integer align:#left width:120	
	)
	group "切割片大小设置"
	(
		spinner spn_sliceLength "切割方块长:" range:[1, 100000000, mlptSettings.slicer_length] type:#integer align:#left width:120 tooltip:"设置每个切割方块的长度（X轴方向）"
        spinner spn_sliceWidth "切割方块宽:" range:[1, 100000000, mlptSettings.slicer_width] type:#integer align:#left width:120 tooltip:"设置每个切割方块的宽度（Y轴方向）"
	)

    group "切割设置"
    (
        dropdownlist ddl_units "单位:" items:#("系统单位", "毫米(mm)", "厘米(cm)", "米(m)", "英寸(in)", "英尺(ft)") selection:mlptSettings.slicer_units width:120 tooltip:"选择长度和宽度的单位"
        checkbox chk_showPreview "显示切割预览" checked:mlptSettings.slicer_previewEnabled tooltip:"在视口中显示切割网格预览线条"
        checkbox chk_createNewObjects "创建新对象" checked:true
        checkbox chk_deleteOriginal "删除原对象" checked:true
        checkbox chk_useOptimizedMethod "使用优化方法（推荐）" checked:true tooltip:"使用更快的切割算法，推荐用于大型模型"
        checkbox chk_applyRandomColors "应用随机线框颜色" checked:true tooltip:"为切割后的每个对象应用随机线框颜色"
    )
    
    group "精度控制"
    (
        radiobuttons rdo_precisionType "计算精度:" labels:#("小数", "整数") default:1 columns:2 tooltip:"选择切割计算使用的数值类型"
        spinner spn_tolerance "对齐容差:" range:[0.001, 100.0, mlptSettings.slicer_tolerance] type:#float align:#left width:120 tooltip:"顶点对齐到边界的容差值，大型模型建议使用较大值"
        spinner spn_largeModelThreshold "大模型阈值:" range:[1000, 100000000, mlptSettings.slicer_threshold] type:#integer align:#left width:120 tooltip:"超过此值的坐标被视为大模型，不进行整数化处理"
        checkbox chk_enableIntegerSnap "启用整数对齐" checked:mlptSettings.slicer_integerSnap tooltip:"是否将顶点坐标对齐到整数，大型模型建议关闭"
        checkbox chk_enablePrecisionMode "高精度模式" checked:mlptSettings.slicer_precisionMode tooltip:"启用双精度计算，适用于超大型模型"
    )
    
    group "快速预设"
    (
        button btn_presetSmall "小模型预设" width:80 height:25 across:3 tooltip:"适用于小于1000单位的模型"
        button btn_presetMedium "中模型预设" width:80 height:25 tooltip:"适用于1000-100000单位的模型"
        button btn_presetLarge "大模型预设" width:80 height:25 tooltip:"适用于超过100000单位的模型"
    )
    
    group "执行"
    (
        button btn_execute "执行切割" width:250 height:30 align:#center
        progressBar pb_progress color:blue value:0 width:250 align:#center
    )
    
    group "颜色工具"
    (
        button btn_applyRandomColors "为选中对象应用随机线框颜色" width:250 height:30 align:#center tooltip:"为当前选中的所有对象应用随机线框颜色"
    )
    
    group "状态"
    (
        label lbl_status "就绪" align:#center
    )
    
    local selectedObj = undefined
    local isUpdatingInternally = false
    
    -- 根据行列数更新自定义尺寸的函数
    fn updateCustomSizeFromRowsColumns =
    (
        if selectedObj != undefined and isValidNode selectedObj then
        (
            -- 获取对象边界
            local objBounds = selectedObj.max - selectedObj.min
            
            -- 根据当前行列数计算每个切割方块的尺寸（系统单位），使用双精度计算避免精度损失
            local sliceLengthInSystemUnits = (objBounds.x as double) / (spn_columns.value as double)
            local sliceWidthInSystemUnits = (objBounds.y as double) / (spn_rows.value as double)
            
            -- 转换为当前显示单位并更新spinner控件，使用精确的四舍五入
            local convertedLength = mlpt_slicer_convertFromSystemUnits sliceLengthInSystemUnits ddl_units.selection
            local convertedWidth = mlpt_slicer_convertFromSystemUnits sliceWidthInSystemUnits ddl_units.selection
            
            -- 使用更精确的四舍五入方法
            spn_sliceLength.value = (floor (convertedLength + 0.5)) as integer
            spn_sliceWidth.value = (floor (convertedWidth + 0.5)) as integer
            
            -- 更新全局设置
            mlptSettings.slicer_length = spn_sliceLength.value
            mlptSettings.slicer_width = spn_sliceWidth.value
            
            -- 更新状态提示
            lbl_status.text = "已根据行列数更新切割尺寸：长=" + (spn_sliceLength.value as string) + ", 宽=" + (spn_sliceWidth.value as string)
        )
    )
    
    -- 获取当前单位的显示名称
    fn getCurrentUnitName =
    (
        case ddl_units.selection of
        (
            1: "系统单位"
            2: "mm"
            3: "cm"
            4: "m"
            5: "in"
            6: "ft"
            default: "系统单位"
        )
    )
    
    -- 更新预览网格
    fn updatePreview =
    (
        if selectedObj != undefined and isValidNode selectedObj and chk_showPreview.checked then
        (
            -- 同步全局变量
            mlpt_slicer_selectedObj = selectedObj
            mlpt_slicer_rows = spn_rows.value
            mlpt_slicer_columns = spn_columns.value
            
            -- 强制重绘视口
            redrawviews()
        )
    )
    
    -- 预览复选框事件
    on chk_showPreview changed state do
    (
        try
        (
            -- 更新全局预览状态
            mlpt_slicer_previewEnabled = state
            mlptSettings.slicer_previewEnabled = state
            
            if state then
            (
                -- 启用预览
                if selectedObj != undefined and isValidNode selectedObj then
                (
                    mlpt_slicer_registerPreview()
                    updatePreview()
                    lbl_status.text = "预览已启用"
                )
                else
                (
                    lbl_status.text = "预览已启用，请选择模型以显示预览"
                )
            )
            else
            (
                -- 禁用预览
                mlpt_slicer_unregisterPreview()
                lbl_status.text = "预览已禁用"
            )
        )
        catch
        (
            local errorMsg = getCurrentException()
            lbl_status.text = "预览功能错误：" + errorMsg
        )
    )
    
    -- 选择模型
    on btn_pickModel picked obj do
    (
        -- 内联处理逻辑，避免函数未定义问题
        if obj != undefined and (superClassOf obj == GeometryClass or isShapeObject obj) then
        (
            selectedObj = obj
            mlpt_slicer_selectedObj = obj
            lbl_selectedModel.text = "已选择: " + obj.name
            
            -- 直接调用数据更新函数，确保切割设置数据正确更新
            isUpdatingInternally = true
            updateCustomSizeFromRowsColumns()
            isUpdatingInternally = false
            
            -- 如果预览已启用，更新预览
            if chk_showPreview.checked then
            (
                updatePreview()
            )
            
            lbl_status.text = "已选择模型并更新数据: " + obj.name
        )
        else
        (
            selectedObj = undefined
            mlpt_slicer_selectedObj = undefined
            lbl_selectedModel.text = "未选择模型"
            lbl_status.text = "选择无效，请选择一个有效的几何体或形状"
        )
    )
    
    -- 小模型预设
    on btn_presetSmall pressed do
    (
        spn_tolerance.value = 0.001
        spn_largeModelThreshold.value = 1000
        chk_enableIntegerSnap.checked = true
        chk_enablePrecisionMode.checked = false
        chk_useOptimizedMethod.checked = true
        rdo_precisionType.state = 1  -- 小数精度
        lbl_status.text = "已应用小模型预设 (容差:0.001, 阈值:1000, 小数精度)"
        
        -- 更新设置
        mlptSettings.slicer_tolerance = spn_tolerance.value
        mlptSettings.slicer_threshold = spn_largeModelThreshold.value
        mlptSettings.slicer_integerSnap = chk_enableIntegerSnap.checked
        mlptSettings.slicer_precisionMode = chk_enablePrecisionMode.checked
        mlptSettings.slicer_precisionType = rdo_precisionType.state
    )
    
    -- 中模型预设
    on btn_presetMedium pressed do
    (
        spn_tolerance.value = 0.1
        spn_largeModelThreshold.value = 100000
        chk_enableIntegerSnap.checked = true
        chk_enablePrecisionMode.checked = false
        chk_useOptimizedMethod.checked = true
        rdo_precisionType.state = 2  -- 整数精度
        lbl_status.text = "已应用中模型预设 (容差:0.1, 阈值:100000, 整数精度)"
        
        -- 更新设置
        mlptSettings.slicer_tolerance = spn_tolerance.value
        mlptSettings.slicer_threshold = spn_largeModelThreshold.value
        mlptSettings.slicer_integerSnap = chk_enableIntegerSnap.checked
        mlptSettings.slicer_precisionMode = chk_enablePrecisionMode.checked
        mlptSettings.slicer_precisionType = rdo_precisionType.state
    )
    
    -- 大模型预设
    on btn_presetLarge pressed do
    (
        spn_tolerance.value = 1.0
        spn_largeModelThreshold.value = 1000000
        chk_enableIntegerSnap.checked = false
        chk_enablePrecisionMode.checked = true
        chk_useOptimizedMethod.checked = true
        rdo_precisionType.state = 2  -- 整数精度
        lbl_status.text = "已应用大模型预设 (容差:1.0, 阈值:1000000, 高精度模式, 整数精度)"
        
        -- 更新设置  
        mlptSettings.slicer_tolerance = spn_tolerance.value
        mlptSettings.slicer_threshold = spn_largeModelThreshold.value
        mlptSettings.slicer_integerSnap = chk_enableIntegerSnap.checked
        mlptSettings.slicer_precisionMode = chk_enablePrecisionMode.checked
        mlptSettings.slicer_precisionType = rdo_precisionType.state
    )
    
    -- rollout初始化事件
    on mlpt_ro_modelslicer open do
    (
        -- 强制清理任何残留的预览回调
        mlpt_slicer_unregisterPreview()
        
        -- 初始化全局预览状态为禁用
        mlpt_slicer_previewEnabled = false
        
        -- 更新spinner的tooltip以显示当前单位
        local unitName = getCurrentUnitName()
        spn_sliceLength.tooltip = "设置每个切割方块的长度（X轴方向），当前单位：" + unitName
        spn_sliceWidth.tooltip = "设置每个切割方块的宽度（Y轴方向），当前单位：" + unitName
        
        -- 确保预览复选框为设置状态
        chk_showPreview.checked = mlptSettings.slicer_previewEnabled
        
        -- 设置精度类型单选按钮的默认值
        rdo_precisionType.state = mlptSettings.slicer_precisionType
        
        -- 初始化预览相关变量
        mlpt_slicer_rows = spn_rows.value
        mlpt_slicer_columns = spn_columns.value
        
        -- 显示初始化完成状态
        lbl_status.text = "就绪 - 已加载默认精度设置"
    )
    
    -- 存储当前单位索引的全局变量
    local currentUnitIndex = 1
    
    -- 根据自定义尺寸更新行列数的函数
    fn updateRowsColumnsFromCustomSize =
    (
        if selectedObj != undefined and isValidNode selectedObj then
        (
            -- 获取对象边界
            local objBounds = selectedObj.max - selectedObj.min
            
            -- 将用户输入的尺寸转换为系统单位（使用双精度计算）
            local sliceLength = mlpt_slicer_convertToSystemUnits (spn_sliceLength.value as double) ddl_units.selection
            local sliceWidth = mlpt_slicer_convertToSystemUnits (spn_sliceWidth.value as double) ddl_units.selection
            
            -- 根据自定义尺寸计算行列数，使用精确的双精度计算
            local newColumns = if sliceLength > 0 then (ceil (objBounds.x as double / sliceLength)) as integer else 1
            local newRows = if sliceWidth > 0 then (ceil (objBounds.y as double / sliceWidth)) as integer else 1
            
            -- 限制最大行列数以防止意外的巨大值
            if newColumns > 10000 then newColumns = 10000
            if newRows > 10000 then newRows = 10000
            
            -- 更新spinner控件的值
            spn_columns.value = newColumns
            spn_rows.value = newRows
            
            -- 更新全局变量
            mlptSettings.slicer_columns = newColumns
            mlptSettings.slicer_rows = newRows
            
            -- 更新状态提示
            lbl_status.text = "已自动更新：行数=" + newRows as string + "，列数=" + newColumns as string
        )
    )
    
    -- 切割方块长度变化事件
    on spn_sliceLength changed val do
    (
        if not isUpdatingInternally then
        (
            isUpdatingInternally = true
            mlptSettings.slicer_length = val
            updateRowsColumnsFromCustomSize()
            isUpdatingInternally = false
            if chk_showPreview.checked then updatePreview()
        )
    )
    
    -- 切割方块宽度变化事件
    on spn_sliceWidth changed val do
    (
        if not isUpdatingInternally then
        (
            isUpdatingInternally = true
            mlptSettings.slicer_width = val
            updateRowsColumnsFromCustomSize()
            isUpdatingInternally = false
            if chk_showPreview.checked then updatePreview()
        )
    )
    
    -- 行数变化事件
    on spn_rows changed val do
    (
        if not isUpdatingInternally then
        (
            isUpdatingInternally = true
            mlptSettings.slicer_rows = val
            -- 根据新的行数更新切割方块尺寸
            updateCustomSizeFromRowsColumns()
            isUpdatingInternally = false
            -- 仅在预览启用时更新预览
            if chk_showPreview.checked then
            (
                updatePreview()
            )
        )
    )
    
    -- 列数变化事件
    on spn_columns changed val do
    (
        if not isUpdatingInternally then
        (
            isUpdatingInternally = true
            mlptSettings.slicer_columns = val
            -- 根据新的列数更新切割方块尺寸
            updateCustomSizeFromRowsColumns()
            isUpdatingInternally = false
            -- 仅在预览启用时更新预览
            if chk_showPreview.checked then
            (
                updatePreview()
            )
        )
    )
    
    -- 精度类型单选按钮变化事件
    on rdo_precisionType changed state do
    (
        mlptSettings.slicer_precisionType = state
        -- 可以在这里添加其他相关的更新逻辑
        if chk_showPreview.checked then updatePreview()
    )
    
    -- 单位下拉菜单变化事件
    on ddl_units selected index do
    (
        if selectedObj != undefined and isValidNode selectedObj and currentUnitIndex != index then
        (
            -- 先将当前显示值转换为系统单位（使用旧单位）
            local currentLengthInSystemUnits = mlpt_slicer_convertToSystemUnits spn_sliceLength.value currentUnitIndex
            local currentWidthInSystemUnits = mlpt_slicer_convertToSystemUnits spn_sliceWidth.value currentUnitIndex
            
            -- 再从系统单位转换为新单位并更新显示，确保整数结果
            spn_sliceLength.value = (floor ((mlpt_slicer_convertFromSystemUnits currentLengthInSystemUnits index) + 0.5)) as integer
            spn_sliceWidth.value = (floor ((mlpt_slicer_convertFromSystemUnits currentWidthInSystemUnits index) + 0.5)) as integer
            
            -- 更新设置
            mlptSettings.slicer_units = index
            mlptSettings.slicer_length = spn_sliceLength.value
            mlptSettings.slicer_width = spn_sliceWidth.value
            
            -- 重新计算行列数
            updateRowsColumnsFromCustomSize()
            
            -- 仅在预览启用时更新预览
            if chk_showPreview.checked then
            (
                updatePreview()
            )
        )
        
        -- 更新当前单位索引
        currentUnitIndex = index
        mlptSettings.slicer_units = index
        
        -- 更新tooltip（无论是否有选择对象都要更新）
        local unitName = case index of
        (
            1: "系统单位"
            2: "mm"
            3: "cm"
            4: "m"
            5: "in"
            6: "ft"
            default: "系统单位"
        )
        spn_sliceLength.tooltip = "设置每个切割方块的长度（X轴方向），当前单位：" + unitName
        spn_sliceWidth.tooltip = "设置每个切割方块的宽度（Y轴方向），当前单位：" + unitName
    )
    
    -- 获取当前选择的对象
    fn getCurrentSelection =
    (
        local selArray = #()
        for obj in selection do
        (
            append selArray obj
        )
        return selArray
    )
    
    -- 应用随机线框颜色到对象
    fn applyRandomColorToObjects objArray =
    (
        try
        (
            -- 显示状态
            lbl_status.text = "正在应用随机线框颜色..."
            
            -- 进度初始化
            pb_progress.value = 0
            local totalObjs = objArray.count
            
            for i = 1 to totalObjs do
            (
                try
                (
                    local obj = objArray[i]
                    
                    -- 更新进度
                    pb_progress.value = 100.0 * i / totalObjs
                    
                    -- 设置随机线框颜色
                    if obj != undefined and isValidNode obj then
                    (
                        obj.wireColor = mlpt_slicer_getRandomColor()
                    )
                )
                catch
                (
                    local errorMsg = getCurrentException()
                    print "========== ModelSlicer applyRandomColorToObjects 单个对象错误 =========="
                    print ("时间: " + (localTime as string))
                    print ("错误信息: " + errorMsg)
                    print ("对象索引: " + (i as string))
                    print ("对象名称: " + (if objArray[i] != undefined then objArray[i].name else "未定义"))
                    print "=================================================================="
                )
            )
            
            -- 更新状态
            lbl_status.text = "已应用随机线框颜色到 " + totalObjs as string + " 个对象"
            pb_progress.value = 100
        )
        catch
        (
            local errorMsg = getCurrentException()
            print "========== ModelSlicer applyRandomColorToObjects 主函数错误 =========="
            print ("时间: " + (localTime as string))
            print ("错误信息: " + errorMsg)
            print ("对象数组大小: " + (objArray.count as string))
            print "=================================================================="
        )
    )
    
    -- 为选中对象应用随机颜色按钮事件
    on btn_applyRandomColors pressed do
    (
        local selObjects = getCurrentSelection()
        
        if selObjects.count == 0 then
        (
            messageBox "请先选择至少一个对象!" title:"错误"
            return()
        )
        
        applyRandomColorToObjects selObjects
    )
    
    -- 执行切割按钮事件
    on btn_execute pressed do
    (
        if selectedObj == undefined then
        (
            messageBox "请先选择一个模型!" title:"错误"
            return()
        )
        
        -- 获取设置
        local rows = spn_rows.value
        local columns = spn_columns.value
        local customLength = spn_sliceLength.value  -- 用户输入的值，将在optimizedSlice中转换
        local customWidth = spn_sliceWidth.value    -- 用户输入的值，将在optimizedSlice中转换
        local useCustomSize = true  -- 始终使用自定义尺寸模式
        local createNew = chk_createNewObjects.checked
        local deleteOrig = chk_deleteOriginal.checked
        local useOptimized = chk_useOptimizedMethod.checked
        local applyColors = chk_applyRandomColors.checked
        
        -- 开始切割
        lbl_status.text = "正在切割..."
        pb_progress.value = 0
        
        -- 冻结界面更新以提高性能
        disableSceneRedraw()
        
        try
        (
            local startTime = timestamp()
            local resultObjects = #()
            
            -- 根据选择的方法执行切割
            if useOptimized then
            (
                -- 使用优化的方法
                resultObjects = mlpt_slicer_optimizedSlice selectedObj rows columns deleteOrig useCustomSize customLength customWidth
            )
            else
            (
                -- 备用的标准切割方法可以在这里实现...
                lbl_status.text = "标准切割方法暂未实现，请使用优化方法"
                return()
            )
            
            -- 如果不创建新对象，则删除所有分割后的对象，只保留原始对象
            if not createNew then
            (
                for obj in resultObjects do
                (
                    delete obj
                )
                resultObjects = #()
            )
            
            -- 如果选择了应用随机颜色，则应用
            if applyColors and resultObjects.count > 0 then
            (
                applyRandomColorToObjects resultObjects
            )
            
            -- 计算执行时间
            local endTime = timestamp()
            local executionTime = ((endTime - startTime) / 1000.0)
            
            -- 更新状态
            lbl_status.text = "切割完成！创建了 " + (resultObjects.count as string) + " 个对象，耗时 " + (executionTime as string) + " 秒"
            pb_progress.value = 100
        )
        catch
        (
            local errorMsg = getCurrentException()
            lbl_status.text = "切割过程中发生错误：" + errorMsg
            
            -- 输出详细错误信息到控制台
            print "========== ModelSlicer 错误报告 =========="
            print ("时间: " + (localTime as string))
            print ("错误信息: " + errorMsg)
            print ("选中对象: " + (if selectedObj != undefined and isValidNode selectedObj then selectedObj.name else "未定义"))
            print ("对象类型: " + (if selectedObj != undefined and isValidNode selectedObj then (classOf selectedObj as string) else "未定义"))
            print ("切割设置:")
            print ("  行数: " + (rows as string))
            print ("  列数: " + (columns as string))
            print ("  自定义长度: " + (customLength as string))
            print ("  自定义宽度: " + (customWidth as string))
            print ("  使用优化方法: " + (useOptimized as string))
            print ("  创建新对象: " + (createNew as string))
            print ("  删除原对象: " + (deleteOrig as string))
            if selectedObj != undefined and isValidNode selectedObj then
            (
                local objBounds = selectedObj.max - selectedObj.min
                print ("对象边界: " + (objBounds as string))
                print ("对象位置: " + (selectedObj.pos as string))
            )
            print "=========================================="
        )
        
        -- 恢复界面更新
        enableSceneRedraw()
        redrawViews()
    )
    
    -- rollout关闭事件
    on mlpt_ro_modelslicer close do
    (
        -- 确保注销预览回调函数
        mlpt_slicer_unregisterPreview()
        -- 清除全局变量
        mlpt_slicer_selectedObj = undefined
        mlpt_slicer_previewEnabled = false
    )
)
-----------------------------------
-- ROLLOUTS END
-----------------------------------

-----------------------------------------------
--CONTAINER DIALOG START
-----------------------------------------------
local tab_rollouts = 
#(
	--#(" 通用 ",#(mlpt_ro_common, mlpt_ro_postprocessing, mlpt_ro_advanced)),
	#(" 通用 ",#(mlpt_ro_common, mlpt_ro_postprocessing)),
	#(" 模型切割 ",#(mlpt_ro_modelslicer))
	--#(" 关于 ",#(mlpt_ro_about, mlpt_ro_debug))
	--#(" 关于 ",#(mlpt_ro_about))

	--#("+",#(mlpt_ro_about))
)

rollout mlpt_dialog_populate populate_title
(
	dotNetControl img_logo "System.Windows.Forms.PictureBox" pos:[5,5] height:68 width:338
	dotNetControl tabs "System.Windows.Forms.TabControl" height:28 width:338 pos:[5,80]
	subRollout subRollout1 width:348 height:(mlptSettings.dialog_height-90) align:#center pos:[5,110] 
	subRollout subRollout2 width:348 height:(mlptSettings.dialog_height-90) align:#center pos:[5,110] visible:off
	subRollout subRollout3 width:348 height:(mlptSettings.dialog_height-90) align:#center pos:[5,110] visible:off
	checkbox chk_interactive "交互式" pos:[190,mlptSettings.dialog_height-34] tooltip:"为已处理的对象实时更新地形设置"
	button btn_process "处理" pos:[269,mlptSettings.dialog_height-47] width:74 height:42 tooltip:"生成地形"
	label lbl_status "" pos:[5,mlptSettings.dialog_height-47] width:175 height:42 style_sunkenedge:true
	progressBar prg_progress "" height:2 color:mlpt_green pos:[0,0] width:350 visible:false
	
	local sub_rollouts = #(subRollout1, subRollout2, subRollout3)

	-----------------------------------------------
	-- DOTNET BASE64 IMAGE DECODER START
	-----------------------------------------------
		--put this in main dialog rollout to be able to access it from outside filein's (framingSystem) using mlpt_dialog_populate.ConvertBase64StringToImage
	local ConvertClass = dotnetclass "system.convert"
	local ImageClass = dotnetclass "system.drawing.image"
	fn ConvertBase64StringToImage string =
	(
		bytearr = convertclass.FromBase64String string
		memstream = dotnetobject "System.IO.MemoryStream" bytearr
		DecodedImg = ImageClass.fromstream memstream
		memstream.close()
		DecodedImg
	)
	-----------------------------------------------
	-- DOTNET BASE64 IMAGE DECODER END
	-----------------------------------------------

	fn dialog_refresh updateStatus:true =
	(
		local new_height=mlpt_dialog_populate.height
		mlptSettings.dialog_height=new_height
		mlpt_dialogPos=GetDialogPos mlpt_dialog_populate

		btn_process.pos.y =  new_height-47
		lbl_status.pos.y = new_height-47
		chk_interactive.pos.y = new_height-34
		prg_progress.pos.y =new_height-55

		for thisRollout in sub_rollouts do
		(
			thisRollout.position.y=110
			thisRollout.height=new_height-162
		)
		
		btn_process.pos.x=269
		tabs.pos.x=5

		if updateStatus do
		(
			if isValidNode mlpt_currentObject then
			(
				objectSelected() --slow?
				
				if chk_interactive.checked then
				(
					--btn_process.enabled=false
				)
				else
				(
					--btn_process.enabled=true
				)
			)
			else
			(
				mlpt_ro_common.drp_meshingmethod.items=#()
				btn_process.enabled=false
			)
			
			if mlpt_returnValue!=undefined and updateStatus do
			(
				case mlpt_returnValue of
				(
					#ok: try(lbl_status.text="状态: 地形已创建。"); catch();
					#emptyResult:try(lbl_status.text="错误: 无法创建地形。"); catch();
				)
				mlpt_returnValue=undefined
			)
			
					--preview grid
			if mlpt_ro_common.chk_preview.checked then register_boundinggrid()
			else unregister_boundinggrid()

			updateAllRolloutSettings()
		)
	)
	fn createTabInterface thisTabControl:tabs=
	(
		thisTabControl.TabPages.Clear()
		thisTabControl.Multiline=false
		thisTabControl.Padding.Y=5
		
		for k=1 to tab_rollouts.count do 
			(
				tabs.TabPages.add tab_rollouts[k][1]
				for r in tab_rollouts[k][2] do addSubRollout sub_rollouts[k] r
			)
	)
	
	on tabs selected sel do 
	(
		for k=0 to tabs.TabPages.count-1 do sub_rollouts[k+1].visible = (k == sel.TabPageIndex)
		
		-- 根据选中的标签页启用/禁用交互复选框和处理按钮
		if sel.TabPageIndex == 1 then -- 模型切割界面
		(
			-- 禁用通用界面的交互复选框和处理按钮
			chk_interactive.enabled = false
			btn_process.enabled = false
		)
		else -- 通用界面
		(
			-- 启用交互复选框和处理按钮
			chk_interactive.enabled = true
			btn_process.enabled = true
		)
	)
	
	on chk_interactive changed a do 
	(
		dialog_refresh()
		if a==true do mlpt_dialog_populate.doAutoUpdate()
	)
	on btn_process pressed do 
	(
		if selection[1]!=undefined then
			undo off doTerrain()
		else
			messageBox "请先选择一个几何体或样条线对象再执行地形生成操作！" title:"未选择对象" beep:true
	)
	
	fn initImgLogo=
	(
		local cursors = dotNetClass "System.Windows.Forms.Cursors"
		img_logo.cursor= cursors.Hand
	)
	-- 全局变量用于控制图片加载
	global mlpt_lastImageLoadTime = 0
	global mlpt_imageCooldownSeconds = 5
	global mlpt_isImageLoading = false
	global mlpt_imageWebClient = undefined
	global mlpt_imageLoadTimeout = 8000  -- 8秒超时
	global mlpt_imageUrls = #(
		"https://tu.ltyuanfang.cn/api/fengjing.php",
		"https://imgapi.cn/bing.php?rand=true",
		"https://imgapi.cn/api.php?zd=pc&fl=fengjing&gs=images",
		"https://imgapi.xl0408.top"
	)
	

	
	-- 异步下载完成回调函数
	fn onImageDownloadCompleted sender args =
	(
		try
		(
			mlpt_isImageLoading = false
			
			if args.Error == undefined and not args.Cancelled then
			(
				local imageBytes = args.Result
				local memStream = dotNetObject "System.IO.MemoryStream" imageBytes
				local networkImage = (dotNetClass "System.Drawing.Image").FromStream memStream
				
				-- 关闭流
				memStream.close()
				
				-- 设置图片并启用拉伸显示（显示完整图片）
				img_logo.Image = networkImage
				img_logo.SizeMode = (dotNetClass "System.Windows.Forms.PictureBoxSizeMode").StretchImage
				
				-- 清理旧的背景图片
				if img_logo.backgroundImage != undefined do
				(
					try
					(
						img_logo.backgroundImage.dispose()
						img_logo.backgroundImage = undefined
					)
					catch()
				)
				

				
				print "随机风景图片加载成功"
			)
			else
			(
				local errorMessage = "网络连接失败"
				if args.Error != undefined then
					errorMessage = args.Error.Message
				else if args.Cancelled then
					errorMessage = "图片下载被取消"
					
				print ("网络图片下载失败: " + errorMessage)
				
				-- 网络失败时使用默认图片
				print "网络连接失败，使用默认图片"
			)
		)
		catch
		(
			mlpt_isImageLoading = false
			print ("图片下载回调处理失败: " + getCurrentException())
			
			-- 出错时使用默认图片
			print "图片下载出错，使用默认图片"
		)
		
		-- 清理WebClient
		if mlpt_imageWebClient != undefined do
		(
			try
			(
				mlpt_imageWebClient.dispose()
				mlpt_imageWebClient = undefined
			)
			catch()
		)
	)
	
	-- 检查是否在冷却时间内
	fn isImageLoadOnCooldown =
	(
		local currentTime = timestamp()
		local timeSinceLastLoad = currentTime - mlpt_lastImageLoadTime
		return (timeSinceLastLoad / 1000.0) < mlpt_imageCooldownSeconds
	)
	
	-- 获取剩余冷却时间（秒）
	fn getRemainingCooldownTime =
	(
		local currentTime = timestamp()
		local timeSinceLastLoad = (currentTime - mlpt_lastImageLoadTime) / 1000.0
		local remaining = mlpt_imageCooldownSeconds - timeSinceLastLoad
		return (if remaining > 0 then remaining else 0)
	)
	
	-- 随机选择一个图片URL
	fn getRandomImageUrl =
	(
		local randomIndex = random 1 mlpt_imageUrls.count
		return mlpt_imageUrls[randomIndex]
	)
	
	-- 异步加载网络图片的函数
	fn loadRandomImageAsync =
	(
		-- 检查冷却时间
		if isImageLoadOnCooldown() do
		(
			local remainingTime = getRemainingCooldownTime()
			print ("图片刷新冷却中，请等待 " + (formattedPrint remainingTime format:"1.0f") + " 秒")
			return false
		)
		
		-- 检查是否正在加载
		if mlpt_isImageLoading do
		(
			print "图片正在加载中，请稍候..."
			return false
		)
		
		try
		(
			mlpt_isImageLoading = true
			mlpt_lastImageLoadTime = timestamp()
			
			-- 随机选择一个图片URL
			local imageUrl = getRandomImageUrl()
			print ("开始从URL加载图片: " + imageUrl)
			
			mlpt_imageWebClient = dotNetObject "System.Net.WebClient"
			
			-- 设置用户代理
			try
			(
				-- 添加用户代理以防止某些网站阻止
				mlpt_imageWebClient.Headers.Add "User-Agent" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
			)
			catch()
			
			-- 注册异步下载完成事件
			dotNet.addEventHandler mlpt_imageWebClient "DownloadDataCompleted" onImageDownloadCompleted
			
			-- 开始异步下载
			local uri = dotNetObject "System.Uri" imageUrl
			mlpt_imageWebClient.DownloadDataAsync uri
			
			print "开始异步加载随机风景图片..."
			return true
		)
		catch
		(
			mlpt_isImageLoading = false
			local errorMsg = getCurrentException()
			print ("异步图片加载启动失败: " + errorMsg)
			
			-- 启动失败时使用默认图片
			print "网络连接失败，使用默认图片"
			
			-- 清理WebClient
			if mlpt_imageWebClient != undefined do
			(
				try
				(
					mlpt_imageWebClient.dispose()
					mlpt_imageWebClient = undefined
				)
				catch()
			)
			
			return false
		)
	)
	
	on img_logo MouseUp arg do
 	(
 		if arg.button == arg.button.left AND
 			img_logo.bounds.Contains arg.location do
 				loadRandomImageAsync() -- 使用异步加载函数
 	)

	on mlpt_dialog_populate open do
	(
		initImgLogo()
		-- 对话框打开时不自动加载随机图片
		-- loadRandomImageAsync()  -- 注释掉自动加载
		img_logo.backgroundImageLayout = (dotNetClass "System.Windows.Forms.ImageLayout").stretch
		img_logo.backgroundImage = mlpt_dialog_populate.ConvertBase64StringToImage "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"
		
		createTabInterface()
	
		mlpt_currentObject=getCurrentObject()
		dialog_refresh()
		
		resumeRedraw() --fix stuck mod panel if script previously crashed
		forcecompleteredraw()
	)
	on mlpt_dialog_populate resized thisNewsize do dialog_refresh updateStatus:false
	on mlpt_dialog_populate close do
	(
		mlpt_dialogPos=GetDialogPos mlpt_dialog_populate --store dialog position for next run in current session
		
		unregister_boundinggrid() --remove preview grid callback
		
		-- 清理图片加载相关资源
		try
		(
			-- 如果有正在进行的异步下载，取消它
			if mlpt_imageWebClient != undefined do
			(
				try
				(
					mlpt_imageWebClient.CancelAsync()
					mlpt_imageWebClient.dispose()
					mlpt_imageWebClient = undefined
				)
				catch()
			)
			
			-- 重置图片加载状态
			mlpt_isImageLoading = false
			
			-- 清理图片控件
			if img_logo.backgroundImage != undefined do
			(
				try
				(
					img_logo.backgroundImage.dispose()
				)
				catch()
			)
			
			if img_logo.Image != undefined do
			(
				try
				(
					img_logo.Image.dispose()
				)
				catch()
			)
			
			img_logo.dispose()
		)
		catch
		(
			print ("图片资源清理时出现错误: " + getCurrentException())
		)
		
		mlpt_objChangedRemove no_gc:true
		
		gc lite:true
			--dotNet garbage collection
		local dgc = dotnetclass "system.gc"
		dgc.collect()
		mlpt_dialog_populate=undefined
	)

	fn doAutoUpdate=
	(
		if chk_interactive.checked and selection[1]!=undefined do 
		(
			btn_process.enabled=false
			doTerrain()
			
		)
	)
)
-----------------------------------------------
--CONTAINER DIALOG END
-----------------------------------------------

	--check if max version is 2010 or higher
if (maxversion())[1]<12000 then
	(
		messageBox "抱歉，仅支持3ds Max 2010或更高版本。" title:"错误"
	)
	--run dialog
else createDialog mlpt_dialog_populate mlptSettings.dialog_width mlptSettings.dialog_height pos:mlpt_dialogPos lockWidth:true style:#(#style_titlebar, #style_border, #style_sysmenu, #style_resizing,#style_minimizebox)
	
)
