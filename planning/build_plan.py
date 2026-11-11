from pathlib import Path
from decimal import Decimal
from docx import Document
from docx.shared import Cm, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
import json

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'output'
OUT.mkdir(parents=True, exist_ok=True)
ASSETS = ROOT / 'assets'
ASSETS.mkdir(exist_ok=True)
img = ASSETS / 'mobile_chat_concept.png'
if not img.is_file():
    raise FileNotFoundError(f'Missing planning illustration: {img}')

doc=Document()
sec=doc.sections[0]
sec.page_width=Cm(21); sec.page_height=Cm(29.7)
sec.top_margin=Cm(1.85); sec.bottom_margin=Cm(1.8)
sec.left_margin=Cm(2); sec.right_margin=Cm(2)
sec.footer_distance=Cm(.8)
for grid in list(sec._sectPr.findall(qn('w:docGrid'))): sec._sectPr.remove(grid)

for name in ['Normal','Title','Subtitle','Heading 1','Heading 2','Caption']:
    st=doc.styles[name]
    st.font.name='Microsoft YaHei'
    st._element.get_or_add_rPr().get_or_add_rFonts().set(qn('w:eastAsia'),'Microsoft YaHei')
    st.font.color.rgb=RGBColor(0,0,0)
    st.paragraph_format.space_after=Pt(5)
    for border in list(st._element.iter(qn('w:pBdr'))): border.getparent().remove(border)
    snap=OxmlElement('w:snapToGrid'); snap.set(qn('w:val'),'0'); st._element.get_or_add_pPr().append(snap)
normal=doc.styles['Normal']
normal.font.size=Pt(10.5)
normal.paragraph_format.line_spacing=Pt(15)
normal.paragraph_format.widow_control=True
for name,size in [('Title',24),('Subtitle',11),('Heading 1',17),('Heading 2',12)]:
    st=doc.styles[name]; st.font.size=Pt(size)
    st.paragraph_format.space_before=Pt(8 if name!='Title' else 0)
    st.paragraph_format.space_after=Pt(6)
    st.paragraph_format.keep_with_next=True
doc.styles['Caption'].font.size=Pt(9)
doc.core_properties.title='二次元 AI 陪伴软件第一版项目企划书'
doc.core_properties.subject='个人开发 外部 API 低预算 手机端'
doc.core_properties.author='项目团队'
doc.core_properties.keywords='AI陪伴,二次元,项目企划书,MVP,API,成本'

fp=sec.footer.paragraphs[0]; fp.alignment=WD_ALIGN_PARAGRAPH.RIGHT
r=fp.add_run('第一版项目企划书  |  '); r.font.size=Pt(8)
fld=OxmlElement('w:fldSimple'); fld.set(qn('w:instr'),'PAGE'); fp._p.append(fld)

def p(text='',bold=False,style=None):
    a=doc.add_paragraph(style=style)
    r=a.add_run(text); r.bold=bold
    return a
def h(text,level=2): return doc.add_heading(text,level)
def page(title):
    a=h(title,1); a.paragraph_format.page_break_before=True
def table(headers,rows,widths):
    t=doc.add_table(rows=1, cols=len(headers))
    t.alignment=WD_TABLE_ALIGNMENT.CENTER; t.autofit=False
    for c,w in zip(t.columns,widths): c.width=Cm(w)
    borders=OxmlElement('w:tblBorders')
    for edge in ['top','left','bottom','right','insideH','insideV']:
        el=OxmlElement('w:'+edge); el.set(qn('w:val'),'single'); el.set(qn('w:sz'),'4'); el.set(qn('w:color'),'D9D9D9'); borders.append(el)
    t._tbl.tblPr.append(borders)
    for i,row in enumerate([headers]+rows):
        cells=t.rows[0].cells if i==0 else t.add_row().cells
        trpr=cells[0]._tc.getparent().get_or_add_trPr()
        nosplit=OxmlElement('w:cantSplit'); trpr.append(nosplit)
        if i==0:
            rep=OxmlElement('w:tblHeader'); trpr.append(rep)
        for j,(c,txt,w) in enumerate(zip(cells,row,widths)):
            c.width=Cm(w); c.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
            tcpr=c._tc.get_or_add_tcPr()
            cb=OxmlElement('w:tcBorders')
            for edge in ['top','left','bottom','right']:
                be=OxmlElement('w:'+edge); be.set(qn('w:val'),'single'); be.set(qn('w:sz'),'4'); be.set(qn('w:color'),'D9D9D9'); cb.append(be)
            tcpr.append(cb)
            mar=OxmlElement('w:tcMar')
            for e,v in [('top',85),('bottom',85),('left',105),('right',105)]:
                el=OxmlElement('w:'+e); el.set(qn('w:w'),str(v)); el.set(qn('w:type'),'dxa'); mar.append(el)
            tcpr.append(mar)
            shade=OxmlElement('w:shd'); shade.set(qn('w:fill'),'E6EDF3' if i==0 else ('F7F9FB' if i%2==0 else 'FFFFFF')); tcpr.append(shade)
            pp=c.paragraphs[0]; pp.paragraph_format.space_after=Pt(0); pp.paragraph_format.line_spacing=1.15
            if j==0: pp.alignment=WD_ALIGN_PARAGRAPH.CENTER
            rr=pp.add_run(str(txt)); rr.font.size=Pt(9.5); rr.bold=i==0
    spacer=p(); spacer.paragraph_format.space_after=Pt(3); spacer.paragraph_format.line_spacing=Pt(2)
    for run in spacer.runs: run.font.size=Pt(1)
    return t

def link(label,url):
    a=doc.add_paragraph(); a.paragraph_format.space_after=Pt(8)
    a.add_run(label+'\n').bold=True
    rel=a.part.relate_to(url,'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink',is_external=True)
    e=OxmlElement('w:hyperlink'); e.set(qn('r:id'),rel)
    rr=OxmlElement('w:r'); pr=OxmlElement('w:rPr'); col=OxmlElement('w:color'); col.set(qn('w:val'),'28536B'); pr.append(col)
    sz=OxmlElement('w:sz'); sz.set(qn('w:val'),'17'); pr.append(sz); rr.append(pr)
    txt=OxmlElement('w:t'); txt.text='查看官方资料'; rr.append(txt); e.append(rr); a._p.append(e)

# 1
p('二次元 AI 陪伴软件',style='Title')
p('第一版项目企划书',style='Subtitle')
p('个人开发实施方案    版本 1.0    2026年11月9日')
h('1 项目定位与实施结论',1)
p('面向国内二次元爱好者，提供可自行定义形象、声音和性格的日常聊天伙伴。用户通过上传图片、声音样本和性格文字创建私有角色，在手机上以文字或语音交流，并看到与对话相符的简单表情和动作。')
p('第一版采用手机 H5、轻量后端与外部 API。开发者自己实现角色档案、聊天流程、基础记忆、动画展示和费用管理；对话、语音与图片编辑调用外部服务。先完成个人原型，再完成具备核心体验的内测版本，最后按国内上线要求组织用户测试。')
table(['事项','第一版建议'],[
('用户与场景','二次元角色创建与日常陪伴；首轮测试建议限定成年用户，角色默认私有。'),
('交付载体','先做手机浏览器可用的 H5。优先验证 Android Chrome 和 iOS Safari；原生 App 后续决定。'),
('核心体验','上传图片与音色、编辑性格、文字聊天、按住说话、语音回复、有限表情动作、可管理记忆。'),
('人力与周期','1 名开发者，预计 180～260 小时；按每周 20 小时约 9～13 周，另留联调缓冲。'),
('资金安排','先预留 600～1000 元技术验证资金；10 名平均日活用户的常规技术运行预算约 210～330 元/月。')
],[3,14])
p('资金估算按第 9 和第 10 节的用量假设计算，不含自己的劳动、设备、正式上线所需专业服务和人工运营。API 接入能降低算力投入，但不能保证图片效果、角色质量或上线手续自动满足要求。')
h('首版成功的判断')
p('普通用户能独立创建角色；连续聊天时性格基本一致；更换声音后能明显听到差异；表情能随对话改变；重要信息可以记住并纠正。先验证用户愿意再次回来聊天，再决定付费方案与扩展功能。')

# 2
page('2 必须做与暂缓做的功能')
p('P0 表示完整内测版必须具备。个人原型可先只实现图片、性格和文字聊天，但不能把该原型视为三个核心卖点已全部完成。以下限制值是初始产品参数，可根据测试调整。')
table(['模块','P0 范围','边界与完成条件'],[
('角色档案','创建、修改、删除；每人先限 2 个角色','图片、音色、性格、记忆相互绑定；修改有版本。'),
('图片上传','PNG/JPG，单张不超过 5 MB；裁剪预览','引导单人正面半身图；不合适的素材有明确提示。'),
('表情动作','原图＋3 种表情；微幅摆动与状态切换','由图片编辑生成表情供预览；只晃动原图不算表情验收通过。'),
('性格设置','表单、粘贴、UTF-8 TXT 上传','先限 5000 汉字；解析为可编辑字段，用户确认后生效。'),
('文字聊天','流式显示、历史记录、停止与失败重试','角色身份稳定；重试不重复保存同一条消息。'),
('语音输入','按住录音，最长 30 秒，转写后可修改发送','拒绝麦克风权限时仍可打字；短录音识别可用。'),
('音色定制','上传样本、创建音色、试听、更换、删除','仅接受本人或获授权素材；失败可退回预设音色。'),
('语音回复','按需播放、可选自动朗读、停止播放','使用该角色绑定音色；切换角色后停止上一段声音。'),
('基础记忆','近期对话＋摘要＋用户确认的重要信息','能查看、纠正、删除；区分角色背景和用户事实。'),
('账号资料','邀请账号、会话登录、资料隔离、导出删除','所有资源检查归属；用户只能读取自己的角色与对话。'),
('用量管理','按人限额、全局预算、失败记录、管理开关','每次付费调用前检查额度；可停止新建音色和生成图片。'),
('服务基础','AI 身份提示、反馈入口、退出与数据告知','对外提供前补齐第 11 节列出的适用上线条件。')
],[2.4,6.6,8])
h('后续版本')
p('实时自由插话、全身动画、Live2D/3D 导入、写实真人、专业声音模型导入、自动性格成长、换装小游戏、主动通知、角色市场、支付订阅和原生双端 App 暂缓。Word/PDF 性格文档也留到 TXT 流程稳定之后。')

# 3
page('3 用户流程与界面方向')
p('进入邀请账号 → 创建角色 → 上传图片并预览表情 → 上传或选择声音并试听 → 填写或导入性格 → 试聊三句话 → 保存并进入聊天。图片和性格可先完成，声音和表情生成任务在后台继续，页面显示真实进度与失败原因。')
a=doc.add_paragraph(); a.alignment=WD_ALIGN_PARAGRAPH.CENTER; a.paragraph_format.line_spacing=1
shape=a.add_run().add_picture(str(ASSETS/'mobile_chat_concept.png'),height=Cm(16))
shape._inline.docPr.set('descr','手机端聊天概念图，上方为二次元角色，下方为聊天记录、形象声音性格入口与按住说话按钮。')
p('图 1  已认可的聊天主界面方向  角色名称与形象仅作示例',style='Caption').alignment=WD_ALIGN_PARAGRAPH.CENTER
p('主界面保留角色展示、消息区、形象/声音/性格入口。开发时让输入区随键盘上移，长消息区可展开；文字与语音输入采用模式切换，避免两个输入区同时占用高度。静态示意图不代表动画、口型或实时通话已经实现。')
p('第一版页面共 5 类：登录与邀请码、角色列表与创建、聊天、角色设置、资料与用量。表情编辑和音色试听可作为设置页中的步骤，不另建复杂工作台。')

# 4
page('4 API 技术架构与选型')
p('建议使用一套前后端分离但同仓库的单体应用。手机只负责交互、录音和播放；后端处理鉴权、角色上下文、模型调用、数据保存与预算。开发阶段无需 GPU、向量数据库或多服务集群。')
table(['层次','建议方案','负责内容'],[
('手机前端','React＋TypeScript＋Vite','移动布局、录音、流式文字、音频播放、图片切换与轻量动画。'),
('业务后端','Node.js＋TypeScript＋Fastify','统一 API、账户权限、模型适配器、计费记录、异步任务。'),
('数据','SQLite 单实例起步','角色、会话、记忆、用量；事务控制，定期备份，负载增加再迁移。'),
('素材','开发时私有文件目录；部署后私有对象存储','图片和音频独立保存，使用有时效的访问链接。'),
('部署','国内轻量云主机＋HTTPS 反向代理','静态前端与后端共机；后台任务先用数据库任务表和单个 worker。'),
('外部能力','优先同一平台接入，保留适配层','对话、识别、合成、音色创建、图片编辑可分别替换。')
],[2.5,6.1,8.4])
h('首轮 API 候选')
p('以阿里云百炼华北2（北京）为首轮集成候选。对话先测 qwen-flash，语音识别测 paraformer-realtime-v2，声音复刻与合成测 cosyvoice-v3-flash，表情图编辑测 wanx2.1-imageedit。以上为开发与测算基线，最终以账号实际可开通能力、试听与延迟测试决定，不代表已验证最优。[1][2][3][5]')
h('一次聊天的数据路径')
p('① 手机上传文字或短录音。② 后端验证用户、角色归属和额度；录音转为模型接受的格式后识别。③ 组合角色档案、近期消息和必要记忆，请求对话 API。④ 分块返回经过校验的正文并保存结果；需要播报时分句合成并排队播放。⑤ 将受限情绪标签映射到现有表情，写入本次用量与延迟。')
p('初始设置建议使用非思考模式、短回复和有限上下文。不得向前端返回平台密钥。对话接口、音色接口和图像接口分别封装，不假定同一平台的所有模型都兼容同一种协议。[4]')
h('手机录音的现实约束')
p('浏览器麦克风访问需要安全上下文与用户授权。必须通过 HTTPS 测试真机，检测录音编码能力，按需在后端转码；微信内置浏览器暂列兼容性扩展，不作为首轮唯一入口。音频播放被阻止时提供手动播放。[6]')

# 5
page('5 接口设计与角色记忆')
p('所有业务接口均由我们的后端提供。数据库中的 user_id 来自登录会话，不接受前端任意指定。目录建议为 apps/web、apps/server、packages/shared、storage 和 docs；这是后续代码组织方案。')
table(['接口组','建议入口','主要结果'],[
('角色','POST/GET/PATCH /api/characters','建立与读取角色；字段变化产生设定版本。'),
('素材任务','POST /api/assets 与 GET /api/jobs/:id','上传文件；状态为排队、处理中、完成或失败。'),
('音色','POST /api/voices 与 DELETE /api/voices/:id','异步创建与删除；记录供应商、模型、地域和 voice_id。'),
('聊天','POST /api/chat/stream','以 fetch 流读取增量事件：正文、情绪、用量、结束、错误。'),
('语音','POST /api/asr 与 POST /api/tts','短录音转写；按消息与音色版本合成/读取缓存。'),
('记忆资料','/api/memories 与 /api/account/export','确认和管理记忆；导出、删除数据及查询用量。')
],[2.5,7.5,7])
h('设定与记忆的组合方式')
p('固定系统规则规定服务边界与输出格式。角色档案包含名字、身份背景、性格、语言习惯、称呼、关系设定与示例对话。每次请求再加入用户确认的记忆、已有对话摘要、最近消息和当前输入。上传的文档是设定素材，不可覆盖系统规则或获取其他用户资料。')
p('基础记忆先实现人工可控流程：用户点“记住这件事”，确认后写入。系统摘要只用于压缩历史，不自动变成永久事实。记忆记录来源消息、时间与确认状态。删除某项记忆时同步清理相关摘要和缓存，并提示仍保留在原聊天记录中的内容可能再次被读取。')
p('先将总输入预算限制在约 6000 Token，优先保留身份、确认记忆与最新消息，历史部分做滚动摘要。成本模型按平均每轮 3000 输入 Token 计算；需要根据接口 usage 统计校准。单次输出设上限，默认回复约 50～100 汉字，可由用户要求展开。')
h('状态和异常处理')
p('模型正文与表情控制信息分离。后端只接受平静、开心、疑惑、难过等白名单标签；无标签或格式错误时使用平静，不把 JSON 或控制符显示给用户。文本和音频使用消息 ID 与序号对齐；取消播放后丢弃旧队列。')
p('客户端提供 request_id 防止重复入库。明确失败的可重试请求采用有上限的退避；音色创建、图片生成和结果不明的付费请求先查询任务，不盲目重复提交。平台返回 429/超时有可理解的提示。')

# 6
page('6 形象声音与素材处理')
h('用有限表情实现第一版生动感')
p('图片路线优先验证“上传原图 → 生成开心、疑惑、难过三张表情 → 用户选择 → 手机缓存切换”。预设轻微摆动表达待机状态；只有生成素材确实包含局部变化时才提供眨眼或点头。连续口型同步与自然身体动作留到后续，不以整图缩放冒充已解决。')
p('先准备 20 张符合输入规范、画风不同的授权图片。每张最多生成 6 张候选，检查脸型、发色、衣服与构图是否保持一致，表情是否可辨识。图像编辑 API 能执行编辑任务，但不保证角色一致性或动画效果；其异步任务和结果有效期需要后端处理。[5]')
p('若至少 16 张能产生可接受的三种表情，可进入受限素材内测；若失败率较高，先收紧图片要求或更换方案再测。原图聊天可以作为故障降级，但完整内测版的表情功能不能据此视为通过。该阈值是项目目标，尚无测试结果。')
h('声音处理流程')
p('页面引导上传清晰、单人、无背景音乐的授权样本，产品初始引导长度为 10～20 秒，实际格式、时长与采样率按所选模型校验。创建完成后试听两句中文，满意后绑定角色。保存 voice_id 以及目标模型和地域；音色通常绑定创建时的模型，切换模型要重新创建。[2]')
p('按消息内容、音色版本与语速生成缓存键；同一段声音再次播放优先使用已有结果。用户停止播放时取消后续合成，但已经提交给供应商的任务仍可能计费。初版先固定正常语速，扩展声音情绪控制前单独试听验证。')
h('数据与素材的生命周期')
table(['数据','保存策略','删除与访问'],[
('角色与消息','私有数据库；每日备份','检查归属；支持导出；删除后同步失效相关缓存。'),
('图片与表情','私有素材存储；客户端缓存','短时授权访问；删除角色时进入清理任务。'),
('声音样本','创建和调试所需的最短保存期','默认处理结束后 24 小时内清理自有临时样本；供应商留存另行告知。'),
('合成音频','建议保留 7 天缓存','过期重播可能重新计费；删除请求需清理自有缓存。'),
('用量与日志','记录 ID、时间、模型、状态和消耗','默认不打印完整聊天、密钥或声音样本；法定日志要求另行落实。')
],[3,7,7])
p('备份建议滚动保留 7 天并记录删除标记，恢复备份时再次执行删除；与供应商侧删除能力、用户告知内容保持一致。图片、声音和原始聊天传给外部 API 前，应明确说明接收方与用途。')

# 7
page('7 个人开发步骤与工时')
p('按具备基础 Web 开发能力、每周约 20 小时投入规划。下表共 180～260 小时，对应约 9～13 周有效开发；再预留 1～2 周真机联调缓冲。若需从头学习或每周仅有 10 小时，应进一步延长周期。外部办理、专业评估或等待审核另计。')
table(['阶段','工时','具体工作','阶段交付'],[
('A 技术验证','20～28 h','跑通对话、音色、短音频识别；完成 20 张图片测试；记录真实价格与延迟。','能力验证记录；图片与声音通过或明确收缩范围。'),
('B 文字原型','28～40 h','建项目、角色档案、图片预览、性格表单、TXT 解析、文字聊天与历史。','自己在手机浏览器完成创建和连续聊天。'),
('C 语音闭环','28～40 h','录音、转码、转写、音色异步创建、试听、语音播放与取消。','用户说话后得到自定义声音回复。'),
('D 表情与记忆','28～40 h','表情任务与切换；消息标签；确认记忆、摘要、删除与更新。','表情随内容变化，重新打开后能延续对话。'),
('E 多用户基础','28～40 h','邀请账号、资源隔离、预算计数、用量页、资料导出删除、反馈入口。','两个账号互不串数据，预算耗尽可阻止新请求。'),
('F 联调部署','28～42 h','HTTPS、真机与异常测试、备份恢复、响应内容管理、上线资料准备。','可演示版本、测试记录、部署回滚说明。'),
('G 小规模验证','20～30 h','上线条件满足后邀请测试；访谈、用量分析、修复高频问题。','完成首轮反馈与继续投入判断。')
],[2.5,2,7.5,5])
h('第一周具体任务')
p('第 1 天：建立仓库与环境变量示例，接通一次对话 API，保存模型、输入输出用量和耗时。第 2～3 天：完成上传图片与性格表单的手机页面，接入文字回复。第 4～5 天：分别验证一段授权声音和五张图片；若效果不合格，优先修正输入要求。余下时间整理失败样例与成本，不急着做完整动画引擎。')
h('开发协作方式')
p('开发者负责产品取舍、服务账号开通、素材授权和真机体验判断；AI 助手协助拆任务、写代码、接口联调、测试与文档。每个阶段使用可运行演示验收，保存变更记录和回退点。涉及代码或配置变更，先说明具体修改方案，再按开发者确认的范围实施。')

# 8
page('8 验收方法与迭代判断')
p('下面是建议验收目标，不是现有性能承诺。先固定模型版本、手机、网络和样本，再记录通过率与失败原因；只用一张图或一次成功对话不能证明稳定。')
table(['项目','建议验收方式与门槛'],[
('创建流程','5 名不了解项目的成年测试者中至少 4 名能独立完成角色创建；等待任务时可看进度。'),
('图片效果','20 张合规输入图片中至少 16 张获得身份一致且可辨别的三种表情；用户可拒绝结果。'),
('性格一致','3 种角色各运行 30 轮固定话题；身份、称呼不矛盾；人工逐条检查语气与回复长度。'),
('语音质量','至少 5 段获授权样本，每段试听 3 句；本人/授权者认可相似度；无明显漏字、爆音和串音色。'),
('基础记忆','10 项确认事实，跨会话可准确读取；纠正与删除后不再作为有效记忆；角色间不串记忆。'),
('响应速度','目标：普通网络下文字首段 P50≤3 秒；松开录音至听到首段声音 P50≤6 秒。每类至少测 50 次，同时报告 P95。'),
('权限与计费','跨账号读取拒绝；重复提交不重复入库；额度检查原子执行；并发请求不能绕过全局预算。'),
('手机与异常','Android Chrome 和 iOS Safari 各一台真机；测试拒绝录音、断网、429、超时、切后台与停止播放。'),
('恢复与删除','从备份成功恢复测试账号；执行删除并检查数据库、文件、摘要、音色任务和缓存。')
],[3,14])
h('首轮用户验证')
p('先从 5～10 名符合测试范围的用户开始，稳定后再扩大到 20～30 名。记录创建完成率、实际聊天天数、语音使用占比、每人费用和主动反馈。建议用“10 人中至少 4 人在一周内主动使用 3 天”作为初步讨论门槛；小样本只提供方向，不代表市场结论。')
h('何时调整范围')
p('若用户只试用一次，优先检查性格、声音和回复是否符合期待；若语音慢，先优化短句与流水播放；若图片常变脸，暂停扩充画风；若费用高，先降低默认朗读比例和历史长度。暂不通过新增社区、游戏或付费系统掩盖核心体验问题。')
p('当前最大的投入风险是图片一致性、语音等待时间、角色持续吸引力与对外上线工作量。阶段 A 结束后重新评估工期；未通过的核心能力不进入大规模开发。')

# 9
page('9 API 单价与成本计算口径')
p('以下为 2026年11月9日核查的公开价格，按华北2（北京）对应模型计算；不扣免费额度、促销或缓存折扣。实际下单与账单以供应商当期控制台为准。图片编辑和音色创建均须先确认账号可用。[1][2]')
table(['能力','测算模型','采用单价'],[
('对话','qwen-flash，输入不超过 128K','输入 0.15 元/百万 Token；输出 1.5 元/百万 Token'),
('语音识别','paraformer-realtime-v2','0.00024 元/秒，即 0.0144 元/分钟'),
('语音合成','cosyvoice-v3-flash','1 元/万计费字符；汉字按 2 字符，其他字符按规则统计'),
('创建音色','上述 CosyVoice 方案','当前创建音色免费；试听与后续合成按用量收费'),
('表情图编辑','wanx2.1-imageedit','0.14 元/张；重复生成增加图片张数')
],[2.6,6.2,8.2])
h('基准用户假设')
p('每位日活用户每天 50 轮对话，一轮指一次用户输入和一次角色回答；每月按 30 天。每轮平均输入 3000 Token，输出 200 Token。25% 的轮次使用语音输入，每段 10 秒；25% 的回答被合成播放，每次按 100 个汉字＋10 个其他字符，即 210 个计费字符。两种 25% 分别计算。')
p('对话模型费用额外增加 20%，覆盖摘要、性格解析与少量额外请求。该比例是预算假设，应使用真实 usage 校准。200 输出 Token 与 100 汉字仅是分别用于文本及语音的近似用量，不是固定换算关系。')
table(['每用户每月项目','计算','金额'],[
('对话与辅助请求','1500 × (3000×0.15＋200×1.5) ÷ 1000000 × 1.2','1.35 元'),
('语音识别','1500 × 25% × 10秒 × 0.00024','0.90 元'),
('语音合成','1500 × 25% × 210 ÷ 10000 × 1','7.875 元'),
('合计','上述三项相加；不含图片与基础设施','约 10.13 元')
],[4,10,3])
p('同样每天 50 轮，如果输入与回复都变为 100% 语音，每人每月 API 费用约为 1.35＋3.60＋31.50＝36.45 元。可见语音比例会显著改变预算。一次重复播放命中自有缓存时通常无需再次合成；测算未计入这项节省。')
p('单个角色的表情任务按 3 张成品、最多 6 张候选估算，上限约 0.84 元图像 API 费用；这只是限定尝试次数下的费用上限，不保证生成成功，也不含人工修图、存储和传输。')

# 10
page('10 运行预算与费用控制')
p('“平均日活”指每天实际使用的人数，不是注册总人数。下表统一采用第 9 节的基准用户；月 API 费用与平均日活成比例。基础设施为规划预留，未取得云主机报价，包含主机、少量素材存储/流量、备份和日志。')
table(['平均日活','月 API 费','基础设施预留','建议月预算'],[
('1 人本地自测','约 10 元','0 元起，使用已有电脑','API 试验另限 100～200 元'),
('10 人','约 101 元','60～150 元/月','210～330 元'),
('30 人','约 304 元','100～200 元/月','530～660 元'),
('100 人','约 1013 元','150～350 元/月','1520～1780 元')
],[2.8,3.5,5.7,5])
p('建议月预算＝（API 费用＋基础设施预留）×1.3，取便于管理的近似整数。30% 缓冲用于用量偏差、失败重试与小额杂费；不包括图片新建费用。100 人全语音时，仅 API 费用约 3645 元/月。')
h('第一笔资金如何安排')
table(['用途','规划金额','说明'],[
('API 验证','100～200 元','对话和声音评测、20 张图片共最多 120 次编辑；图像部分约 16.8 元。'),
('域名','50～100 元/年','按普通域名预留，实际以注册及续费报价为准。'),
('10 人一个月运行','210～330 元','包含上一表的运行缓冲；需要完成上线适用条件。'),
('初始角色素材','不超过 20 元','10 人各最多 2 个角色、每角色最多 6 张候选，图像费约 16.8 元。')
],[4,4,9])
p('上述合计约 380～650 元。建议首次技术验证资金预留 600～1000 元，分批充值，未用部分保留。已有设备与工具按增量 0 元计算；新增工具订阅、独立内容审核/实名核验服务、人工美术、上线评估/咨询、运营值守、投放与原生应用发行费用均未纳入，需另立预算。')
h('把预算控制写进程序')
p('初始单用户建议：每天 50 轮、语音识别 150 秒、合成 3000 个计费字符；每人 2 个角色，图片候选次数有限，音色重建每周限 2 次。额度由后端校验，管理员可配置。')
p('每次调用先按输入和最大输出预占预算，完成后用实际消耗结算；并发使用数据库事务。结果未知的请求保留占额待核对。全局预算 80% 时提醒，达到上限后拒绝新付费任务，保留历史查看、导出和删除。供应商账单可能滞后，应用限额需留余量，每天对账。')

# 11
page('11 国内上线安排与产品边界')
p('个人开发先完成本机技术原型。向国内用户提供持续陪伴服务之前，应把上线条件与技术验收分别落实；使用 H5、邀请码或第三方 API 均不能直接推定免除应用提供者责任。对是否构成面向公众服务及具体办理路径，应向所在地主管部门或合格专业人士确认。')
p('2026年7月15日起施行的《人工智能拟人化互动服务管理暂行办法》覆盖向境内公众提供的持续情感互动服务。其第 22 条涉及上线安全评估与报告提交，第 26 条涉及算法备案；这些是本项目上线计划的实际依赖，不属于本文件技术运行费。[7]')
h('首版需要落实的服务设计')
p('持续显示 AI 身份；用户要求结束时停止互动；提供反馈、投诉和数据导出删除入口；长时间使用提醒；配置内容管理、风险识别和人工应急处置渠道。具体实名、年龄、必要联系人信息与未成年人保护流程按适用要求设计。首轮建议只招募成年测试用户，但仅勾选“已成年”不能替代有效的年龄识别措施。[7]')
p('对声音样本及形象保留授权确认；外部 API 的数据接收方、用途、保存与删除能力写入隐私说明。用户角色文档可以改变风格、称呼和背景，但不能绕过服务规则、访问他人资料或关闭必要的服务提示。')
p('根据 H5 网站或原生 App 的实际部署方式确认备案路径。APP 备案与 AI 相关评估、备案属于不同事项；生成内容的界面提示及可导出文件标识也需按适用规则实现。[8][9]')
h('上线前的执行安排')
p('在阶段 A 同步咨询办理条件与个人主体可行性，记录回复和所需资料；阶段 E/F 实现相应服务功能并整理数据流、接口清单和测试记录。未完成对外服务条件时继续本机验证，不将邀请测试当作当然豁免。由开发者决定何时投入正式上线预算。')
h('商业验证与后续投入')
p('首轮目标是验证角色创建与持续陪伴是否有价值。记录用户最愿意保留的能力及语音使用占比，再考虑“基础文字额度＋有限语音额度＋额外素材创建”的收费结构。付费价格需同时覆盖模型、基础设施、获客、支持与上线运营开销；目前不承诺利润或市场规模。')
p('下一项具体工作是阶段 A 的验证清单与文字原型设计：确认开发环境和供应商账号可用能力，测试一段声音与一组图片，再开始按已确认方案写代码。')

# 12
page('12 参考资料与测算依据')
p('核查日期为 2026年11月9日。价格和能力引用官方资料；工时、使用量、基础设施预留及验收阈值是本项目规划假设。供应商页面、模型与地域会变化，开发接入前需复核。')
refs=[
('[1] 阿里云百炼模型价格  对话 识别 合成与图片费用','https://help.aliyun.com/zh/model-studio/model-pricing'),
('[2] 阿里云声音复刻  创建流程 目标模型绑定与配额','https://help.aliyun.com/zh/model-studio/voice-cloning-user-guide'),
('[3] Paraformer 客户端事件  音频格式与任务流程','https://help.aliyun.com/en/model-studio/paraformer-client-events'),
('[4] 阿里云深度思考  模式开关与流式调用','https://help.aliyun.com/zh/model-studio/deep-thinking'),
('[5] 万相图像编辑  指令编辑与异步任务','https://help.aliyun.com/zh/model-studio/wanx-image-edit'),
('[6] MDN 麦克风访问  安全上下文与用户权限','https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia'),
('[7] 国家网信办 人工智能拟人化互动服务管理暂行办法','https://www.cac.gov.cn/2026-04/10/c_1777558395078289.htm'),
('[8] 工业和信息化部 关于开展移动互联网应用程序备案工作的通知','https://www.miit.gov.cn/jgsj/xgj/wjfb/art/2023/art_dd783a581c9644a4aee10afa582811db.html'),
('[9] 国家网信办 人工智能生成合成内容标识办法','https://www.cac.gov.cn/2025-03/14/c_1743654684782215.htm'),
]
for a,b in refs: link(a,b)
h('版本说明')
p('本版用于安排个人开发与技术验证。界面示意图沿用本次产品讨论中认可的方向；角色名称与美术为示例。功能、成本和周期均未通过实际产品运行验证，阶段 A 完成后更新模型选型、实测延迟、图片通过率与预算。')

# Cost arithmetic is checked independently of displayed rounding.
llm=Decimal(1500)*(Decimal(3000)*Decimal('.15')+Decimal(200)*Decimal('1.5'))/Decimal(1000000)*Decimal('1.2')
asr=Decimal(1500)*Decimal('.25')*Decimal(10)*Decimal('.00024')
tts=Decimal(1500)*Decimal('.25')*Decimal(210)/Decimal(10000)
assert llm==Decimal('1.35') and asr==Decimal('.9') and tts==Decimal('7.875')
costs={'llm_per_user_month':str(llm),'asr_per_user_month':str(asr),'tts_per_user_month':str(tts),'total_per_user_month':str(llm+asr+tts),'full_voice_per_user_month':str(llm+asr*4+tts*4),'source_date':'2026-11-09'}
(ROOT/'cost_check.json').write_text(json.dumps(costs,ensure_ascii=False,indent=2),encoding='utf-8')
path=OUT/'二次元AI陪伴软件_第一版项目企划书_v1.0.docx'
doc.save(path)
print(path)
print(json.dumps(costs,ensure_ascii=False))
