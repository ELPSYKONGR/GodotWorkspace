/* Review-only panel definitions. These proposed fields are not an engine schema. */
window.RV_PANELS = [
  {id:'scene',name:'场景与镜头',kind:'长场景 / 新增',hint:'世界可以很长，视频画幅保持固定。',groups:[
    {name:'世界范围 · 2D 示例',fields:[
      {key:'world_width',label:'宽度',type:'number',value:720,unit:'px',min:100,max:20000},
      {key:'world_height',label:'高度',type:'number',value:20000,unit:'px',min:1280,max:200000},
      {key:'floor',label:'底部边界',type:'select',value:'仅世界底部封闭',options:['仅世界底部封闭','开放，不生成地面']},
      {key:'offscreen',label:'离开画面',type:'select',value:'继续模拟',options:['继续模拟','仅隐藏绘制，继续模拟']}]},
    {name:'成片镜头',fields:[
      {key:'camera_mode',label:'镜头模式',type:'select',value:'纵向跟随',options:['纵向跟随','固定镜头','关键帧轨道（后续）']},
      {key:'target',label:'跟随目标',type:'select',value:'ball_A 的最低存活后代',options:['ball_A 的最低存活后代','指定单个物体','后代群组中心']},
      {key:'framing',label:'目标画面位置',type:'number',value:42,unit:'% 高度',min:10,max:90},
      {key:'smoothing',label:'跟随平滑',type:'number',value:0.18,unit:'s',min:0,max:2,step:0.01},
      {key:'deadzone',label:'竖向死区',type:'vector',value:[32,58],axes:['上','下'],unit:'%'},
      {key:'only_down',label:'镜头只向下',type:'check',value:true},
      {key:'split_policy',label:'目标分裂后',type:'select',value:'沿后代谱系继续跟随',options:['沿后代谱系继续跟随','转为群组取景','保持镜头']}]},
    {name:'编辑视图 · 不写入成片',fields:[
      {key:'depth',label:'查看深度',type:'range',value:3200,min:0,max:18000,step:100,unit:'px'},
      {key:'minimap',label:'显示世界缩略图',type:'check',value:true}]}]},
  {id:'object',name:'物体布置',kind:'现有能力 + 紧凑重排',hint:'位置、尺寸使用成组输入，数值框不再拉满整行。',groups:[
    {name:'选中物体',fields:[
      {key:'name',label:'名称',type:'text',value:'绿色初始球 A'},
      {key:'shape',label:'形状',type:'select',value:'圆球',options:['圆球','长方形','线段障碍','扇区玻璃']},
      {key:'tags',label:'标签',type:'text',value:'ball, splitter'},
      {key:'body_mode',label:'物理模式',type:'select',value:'动态刚体',options:['动态刚体','静态墙体','传感器']}]},
    {name:'变换与尺寸',fields:[
      {key:'position',label:'位置',type:'vector',value:[360,420],axes:['X','Y'],unit:'px'},
      {key:'rotation',label:'旋转',type:'number',value:0,unit:'°',min:-3600,max:3600},
      {key:'radius',label:'半径',type:'number',value:18,unit:'px',min:1,max:500},
      {key:'velocity',label:'初速度',type:'vector',value:[0,80],axes:['X','Y'],unit:'px/s'}]},
    {name:'材质与布置',fields:[
      {key:'visual_ref',label:'视觉材质',type:'select',value:'柔亮绿 / 独立副本',options:['柔亮绿 / 独立副本','共享材质：柔亮绿','共享材质：哑光']},
      {key:'acoustic',label:'声学标签',type:'select',value:'rubber',options:['rubber','metal','wood','glass']},
      {key:'snap',label:'网格吸附',type:'number',value:8,unit:'px',min:1,max:128},
      {key:'locked',label:'锁定布置',type:'check',value:false},
      {key:'visible',label:'显示物体',type:'check',value:true}]}]},
  {id:'material',name:'视觉材质',kind:'逐物体材质 / 新增',hint:'视觉外观独立于物理材质；纯外观修改可复用轨迹。',groups:[
    {name:'材质预设',fields:[
      {key:'material_name',label:'名称',type:'text',value:'柔亮绿'},
      {key:'material_scope',label:'修改范围',type:'select',value:'仅当前物体（独立副本）',options:['仅当前物体（独立副本）','全部引用此共享材质的物体']},
      {key:'shader_mode',label:'显示模式',type:'select',value:'二维荧光',options:['二维平涂','二维荧光','三维 PBR（2.5D / 3D）']},
      {key:'ball_color',label:'基础颜色',type:'color',value:'#53d9a0'},
      {key:'opacity',label:'不透明度',type:'number',value:1,unit:'',min:0,max:1,step:0.01}]},
    {name:'质感 · 按显示模式启用',fields:[
      {key:'roughness',label:'粗糙度',type:'number',value:0.28,unit:'',min:0,max:1,step:0.01},
      {key:'metallic',label:'金属度',type:'number',value:0.05,unit:'',min:0,max:1,step:0.01},
      {key:'glow',label:'发光强度',type:'number',value:0.9,unit:'',min:0,max:3,step:0.05},
      {key:'texture',label:'颜色贴图',type:'text',value:'未指定',placeholder:'项目内相对路径'}]},
    {name:'分裂后的颜色',fields:[
      {key:'inherit_material',label:'子球继承材质',type:'check',value:true},
      {key:'color_generation',label:'代际变化',type:'select',value:'同色系逐代变浅',options:['同色系逐代变浅','保持原色']},
      {key:'lightness_step',label:'每代变浅',type:'number',value:0.06,unit:'',min:0,max:0.3,step:0.01}]}]},
  {id:'physics',name:'物理与碰撞',kind:'现有机制 + 材质补全',hint:'修改物理或分裂规则，需要重新录制轨迹。',groups:[
    {name:'物理材质 · 与外观分开',fields:[
      {key:'mass',label:'质量',type:'number',value:1,unit:'质量单位',min:0.01,max:10000,step:0.01},
      {key:'restitution',label:'弹性',type:'number',value:0.8,unit:'',min:0,max:1,step:0.01},
      {key:'friction',label:'摩擦',type:'number',value:0.05,unit:'',min:0,max:1,step:0.01},
      {key:'ccd',label:'连续碰撞检测',type:'check',value:true}]},
    {name:'碰撞分裂组件',fields:[
      {key:'split',label:'启用分裂',type:'check',value:true},
      {key:'child_count',label:'子球总数',type:'number',value:2,unit:'颗',min:2,max:100},
      {key:'children_split',label:'子球继续分裂',type:'check',value:true},
      {key:'on_ball',label:'球碰球触发',type:'check',value:true},
      {key:'on_wall',label:'球碰墙触发',type:'check',value:true},
      {key:'guard',label:'新生保护',type:'number',value:0.08,unit:'s',min:0,max:1,step:0.01},
      {key:'speed_threshold',label:'最低相对速度',type:'number',value:0,unit:'px/s',min:0,max:100000},
      {key:'hitstop',label:'分裂顿帧',type:'check',value:false}]},
    {name:'安全与诊断',fields:[
      {key:'capacity',label:'动态物体上限',type:'number',value:64,unit:'个',min:2,max:256},
      {key:'show_rejection',label:'显示未分裂原因',type:'check',value:true}]}]},
  {id:'background',name:'场景背景',kind:'纯色已有 / 分层新增',hint:'背景绑定镜头或世界，避免长场景移动后露出空白。',groups:[
    {name:'背景图层',fields:[
      {key:'bg_type',label:'类型',type:'select',value:'渐变',options:['纯色','渐变','图片']},
      {key:'bg_top',label:'主颜色',type:'color',value:'#0c1722'},
      {key:'bg_bottom',label:'次颜色',type:'color',value:'#193e45'},
      {key:'bg_image',label:'图片资源',type:'text',value:'未指定',placeholder:'导入图片后生成相对路径'},
      {key:'bg_fit',label:'图片填充',type:'select',value:'等比覆盖',options:['等比覆盖','等比包含','平铺']}]},
    {name:'空间与滚动',fields:[
      {key:'bg_anchor',label:'绑定空间',type:'select',value:'跟随镜头',options:['跟随镜头','固定在世界','视差图层（后续）']},
      {key:'bg_opacity',label:'不透明度',type:'number',value:1,unit:'',min:0,max:1,step:0.01},
      {key:'bg_offset',label:'偏移',type:'vector',value:[0,0],axes:['X','Y'],unit:'px'},
      {key:'bg_grid',label:'编辑时显示网格',type:'check',value:true}]},
    {name:'三维场景',fields:[
      {key:'environment',label:'环境模式',type:'select',value:'纯色 / 环境光',options:['纯色 / 环境光','天空 / HDRI（后续）']},
      {key:'environment_energy',label:'环境光强度',type:'number',value:0.6,unit:'',min:0,max:4,step:0.05}]}]},
  {id:'collision-audio',name:'碰撞音效',kind:'按对象对路由 / 新增',hint:'球碰球、球碰墙可独立选音色；同一碰撞只调度一次。',routes:[
    ['ball × ball','木质短音','−14 dB'],['ball × wall','金属轻击','−12 dB'],['ball × glass','清脆铃音','−16 dB']
  ],groups:[
    {name:'当前规则 · ball × wall',fields:[
      {key:'sfx_enabled',label:'启用碰撞音',type:'check',value:true},
      {key:'sound',label:'合成音色',type:'select',value:'金属轻击',options:['金属轻击','木质短音','清脆铃音','点击音']},
      {key:'sound_asset',label:'自定义音频',type:'text',value:'未指定',placeholder:'未指定时使用合成音'},
      {key:'sfx_volume',label:'音量',type:'number',value:-12,unit:'dB',min:-60,max:0},
      {key:'sfx_pitch',label:'音高',type:'number',value:1,unit:'倍',min:0.25,max:4,step:0.05},
      {key:'gain_map',label:'强弱依据',type:'select',value:'相对速度估计',options:['相对速度估计','固定强度']}]},
    {name:'密集碰撞处理',fields:[
      {key:'pair_interval',label:'同一物体对间隔',type:'number',value:0.02,unit:'s',min:0,max:1,step:0.005},
      {key:'voices',label:'最大同时声部',type:'number',value:16,unit:'个',min:1,max:32},
      {key:'split_sound',label:'分裂同刻音效',type:'select',value:'用分裂音替代碰撞音',options:['用分裂音替代碰撞音','明确叠加两种音效']},
      {key:'fallback',label:'未命中规则',type:'select',value:'默认点击音',options:['默认点击音','静音']}]}]},
  {id:'music',name:'音乐与环境声',kind:'独立音轨 / 新增',hint:'音乐与碰撞音分开控制；示例路径不附带音频素材。',groups:[
    {name:'背景音乐 · Music 总线',fields:[
      {key:'music_enabled',label:'启用音乐',type:'check',value:true},
      {key:'music_asset',label:'音频资源',type:'text',value:'assets/audio/music/chill.wav'},
      {key:'music_volume',label:'音量',type:'number',value:-22,unit:'dB',min:-60,max:0},
      {key:'music_start',label:'入点',type:'number',value:0,unit:'s',min:0,max:3600,step:0.1},
      {key:'music_loop',label:'循环播放',type:'check',value:true},
      {key:'fade',label:'淡入 / 淡出',type:'vector',value:[0.5,0.8],axes:['入','出'],unit:'s'},
      {key:'duck',label:'碰撞时音乐让位',type:'check',value:true},
      {key:'duck_db',label:'让位幅度',type:'number',value:-5,unit:'dB',min:-18,max:0}]},
    {name:'环境声 · Ambience 总线',fields:[
      {key:'ambient_enabled',label:'启用环境声',type:'check',value:false},
      {key:'ambient_asset',label:'音频资源',type:'text',value:'未指定'},
      {key:'ambient_volume',label:'音量',type:'number',value:-30,unit:'dB',min:-60,max:0},
      {key:'ambient_loop',label:'循环播放',type:'check',value:true}]},
    {name:'播放与导出',fields:[
      {key:'seek_silent',label:'拖动时间轴时静音',type:'check',value:true},
      {key:'sync_clock',label:'音轨时间',type:'select',value:'成片时间（含顿帧）',options:['成片时间（含顿帧）']}]}]},
  {id:'text-effects',name:'文字与特效',kind:'现有能力 + 分组',hint:'屏幕文字固定在画面上，世界标注随镜头移动。',groups:[
    {name:'标题文字',fields:[
      {key:'title',label:'内容',type:'text',value:'小球会落到哪里？'},
      {key:'font',label:'字体',type:'text',value:'Microsoft YaHei'},
      {key:'font_size',label:'字号',type:'number',value:36,unit:'px',min:8,max:120},
      {key:'text_color',label:'颜色',type:'color',value:'#edf5ff'},
      {key:'text_position',label:'位置',type:'vector',value:[44,54],axes:['X','Y'],unit:'px'},
      {key:'text_anchor',label:'绑定空间',type:'select',value:'屏幕',options:['屏幕','世界']}]},
    {name:'碰撞与分裂特效',fields:[
      {key:'trail',label:'拖尾',type:'check',value:true},
      {key:'impact_ring',label:'碰撞光圈',type:'check',value:true},
      {key:'impact_particles',label:'碰撞粒子',type:'check',value:false},
      {key:'split_particles',label:'分裂粒子',type:'check',value:true},
      {key:'particle_count',label:'每次粒子数',type:'number',value:12,unit:'个',min:0,max:64},
      {key:'particle_lifetime',label:'粒子寿命',type:'number',value:0.35,unit:'s',min:0.05,max:3,step:0.05},
      {key:'trail_duration',label:'拖尾长度',type:'number',value:0.2,unit:'s',min:0.03,max:2,step:0.01}]}]},
  {id:'output',name:'视频输出',kind:'现有生产闭环 + 资源补全',hint:'按已录制轨迹逐帧生产，场景长度不改变视频分辨率。',groups:[
    {name:'画幅与时间',fields:[
      {key:'resolution',label:'分辨率',type:'select',value:'1080 × 1920',options:['720 × 1280','1080 × 1920']},
      {key:'fps',label:'帧率',type:'select',value:'60',options:['30','60']},
      {key:'duration',label:'时长',type:'number',value:15,unit:'s',min:1,max:60},
      {key:'render_backend',label:'渲染器',type:'select',value:'Compatibility',options:['Compatibility','Forward+']} ]},
    {name:'生产输入',fields:[
      {key:'take',label:'轨迹',type:'text',value:'outputs/takes/fall_demo.json'},
      {key:'camera_track',label:'镜头',type:'select',value:'使用已烘焙镜头轨道',options:['使用已烘焙镜头轨道','重新计算镜头后生产']},
      {key:'freeze_assets',label:'冻结全部引用资源',type:'check',value:true},
      {key:'export_sfx',label:'包含碰撞音',type:'check',value:true},
      {key:'export_music',label:'包含音乐 / 环境声',type:'check',value:true}]},
    {name:'成片检查',fields:[
      {key:'clean',label:'排除调试界面',type:'check',value:true},
      {key:'file_name',label:'任务名称',type:'text',value:'fall_green_001'},
      {key:'output_note',label:'输出位置',type:'text',value:'outputs/jobs/fall_green_001/'}]}]}
];
