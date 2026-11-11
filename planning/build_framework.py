from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math

# Reuse the typography and table helpers without rebuilding the detailed plan.
source=Path(__file__).with_name('build_plan.py').read_text(encoding='utf-8')
exec(source.split('# 1\n')[0])
doc.core_properties.title='二次元AI陪伴软件第一版整体框架'
doc.core_properties.subject='产品目标 用户体验 模块关系 第一版边界'
doc.core_properties.keywords='产品框架,二次元,AI陪伴,第一版'
doc.styles['Normal'].font.size=Pt(11)
doc.styles['Normal'].paragraph_format.line_spacing=Pt(17)
doc.styles['Normal'].paragraph_format.space_after=Pt(7)
doc.styles['Subtitle'].font.italic=False
fp=sec.footer.paragraphs[0]
fp.clear(); fp.alignment=WD_ALIGN_PARAGRAPH.RIGHT
fp.add_run('第一版整体框架  |  ').font.size=Pt(8)
fld=OxmlElement('w:fldSimple'); fld.set(qn('w:instr'),'PAGE'); fp._p.append(fld)

# A simple product-level module diagram, with no implementation technologies.
im=Image.new('RGB',(1700,650),'white'); draw=ImageDraw.Draw(im)
font=ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc',32)
small=ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc',25)
def box(rect,title,subtitle=None):
    draw.rounded_rectangle(rect,radius=16,fill='#F1F5F8',outline='#8798A5',width=2)
    x1,y1,x2,y2=rect
    draw.text(((x1+x2)/2,(y1+y2)/2-(18 if subtitle else 0)),title,font=font,fill='#17232D',anchor='mm')
    if subtitle: draw.text(((x1+x2)/2,(y1+y2)/2+29),subtitle,font=small,fill='#43525E',anchor='mm')
def arrow(points,both=False):
    draw.line(points,fill='#697E8C',width=4)
    def tip(a,b):
        angle=math.atan2(b[1]-a[1],b[0]-a[0]); l=15
        ends=[b,(b[0]-l*math.cos(angle-.5),b[1]-l*math.sin(angle-.5)),(b[0]-l*math.cos(angle+.5),b[1]-l*math.sin(angle+.5))]
        draw.polygon(ends,fill='#697E8C')
    tip(points[-2],points[-1])
    if both: tip(points[1],points[0])
box((500,15,1200,120),'手机互动界面','角色展示 · 文字与语音 · 定制入口')
box((25,220,465,340),'角色档案','形象 · 声音 · 性格')
box((590,220,1110,340),'对话与陪伴','理解输入 · 结合设定与记忆组织回应')
box((1235,220,1675,340),'角色表现','回答文字 · 声音 · 表情动作')
box((210,470,770,590),'记忆与资料','保存对话 · 记住重要信息 · 用户管理')
box((940,470,1500,590),'外部 AI 能力','通过 API 提供对话与语音等能力')
arrow([(850,120),(850,220)],True)
arrow([(465,280),(590,280)])
arrow([(1110,280),(1235,280)])
arrow([(1455,220),(1455,70),(1200,70)])
arrow([(490,470),(490,400),(720,400),(720,340)],True)
arrow([(1220,470),(1220,400),(980,400),(980,340)],True)
diagram=ASSETS/'product_framework.png'; im.save(diagram)

p('二次元 AI 陪伴软件',style='Title')
p('第一版整体框架    2026年11月10日',style='Subtitle')
h('1 我们要做什么',1)
p('为国内二次元爱好者提供一个手机端的专属 AI 聊天伙伴。用户能自己决定角色长什么样、用什么声音、以什么性格和方式交流，并通过日常聊天建立持续的陪伴体验。')
p('第一版围绕“创建自己的角色 → 开始聊天 → 持续调整与陪伴”形成完整流程。普通用户上传素材、填写设定即可使用，无需自己制作人物模型或训练 AI。')
h('2 用户拿到的产品是什么样子',1)
table(['体验','用户能做什么','软件呈现什么'],[
('定义形象','上传一张二次元角色图片，预览并确认','聊天时显示这个角色，能切换简单表情并呈现轻微动作。'),
('定义声音','上传声音样本，试听并选择使用','角色用所选音色回答；也可先选预设声音。'),
('定义性格','填写或上传性格文档，随时修改','角色按背景、称呼、语言习惯和示例对话交流。'),
('日常交流','打字或按住说话，查看历史记录','以文字、声音和相应表情回应；用户能停止播放。'),
('持续陪伴','确认、修改或删除值得记住的事情','再次聊天时接上近期话题，并使用已确认的重要信息。')
],[2.5,6.4,8.1])
h('3 界面与使用流程',1)
p('沿用已认可的界面方向：上方以角色为主视觉，下方为聊天记录和输入区域；形象、声音、性格均有直接的设置入口。角色展示与聊天相互配合，文字输入和语音输入可以切换。')
p('首次使用：创建角色 → 上传图片 → 上传或选择声音 → 填写或导入性格 → 预览并试聊 → 保存。素材不必一次备齐，可以先用默认选项开始，之后继续修改。')
p('日常使用：选择角色 → 文字或语音聊天 → 查看与管理记忆 → 按需要调整角色。第一版角色默认私有。')
h('4 第一版应达到的结果',1)
p('用户能独立创建一个具有自己选择的形象、声音与性格的角色；文字和语音聊天可正常进行；角色有简单表情动作；再次打开后保留设定和聊天，并能延续已确认的信息。三项定制能力应在完整第一版中同时成立。')

page('5 整体框架与模块关系')
p('产品由手机互动界面、角色档案、对话与陪伴、角色表现、记忆与资料五个部分组成。外部 AI 能力通过 API 为这些部分提供支持；我们负责把它们组织成完整的软件体验。')
a=doc.add_paragraph(); a.alignment=WD_ALIGN_PARAGRAPH.CENTER; a.paragraph_format.line_spacing=1
sh=a.add_run().add_picture(str(diagram),width=Cm(17))
sh._inline.docPr.set('descr','整体产品框架：手机界面连接对话中心，角色档案和记忆为对话提供依据，外部AI提供能力，结果由角色表现模块呈现。')
p('图 1  产品层面的模块关系',style='Caption').alignment=WD_ALIGN_PARAGRAPH.CENTER
table(['部分','主要职责'],[
('手机互动界面','承接创建、设置与聊天操作，让用户看到角色、输入消息、听取回应。'),
('角色档案','统一保存这个角色的形象、声音与性格，作为所有交流和表现的共同依据。'),
('对话与陪伴','结合用户当前输入、角色设定及相关记忆，组织符合角色风格的回应。'),
('角色表现','把回应呈现为文字和声音，并配合简单表情动作，保持同一角色的感受。'),
('记忆与资料','保存角色和聊天记录，管理用户确认的重要信息，支持查看、修改、删除。'),
('外部 AI 能力','通过 API 提供对话、语音识别、声音合成与素材处理等能力；具体服务后续选定。')
],[3.7,13.3])
p('一次交流的整体过程：用户输入 → 读取角色设定和相关记忆 → 调用所需 AI 能力形成回应 → 以角色的文字、声音和表情呈现 → 保存对话，并按用户意愿更新重要记忆。')
h('6 第一版范围',1)
p('必须完成：普通用户的角色创建与修改，图片、声音、性格三项定制，文字与按住说话聊天，简单表情动作，以及基础记忆管理。形象先支持符合要求的二次元单人图片，动作先限定少量预设表现。')
p('后续扩展：专业人物模型和声音资源导入、写实真人、复杂动作、实时连续通话、角色社区与交易等。手机端是产品目标，具体采用网页还是原生应用，以及每个模块的技术方案，在整体框架确认后再细化。')
p('本轮需要确认的是：以上产品目标、用户体验、模块分工和第一版边界是否符合预期。确认后，再把各模块拆成开发任务。')

out=OUT/'二次元AI陪伴软件_整体框架_两页版_v1.0.docx'
doc.save(out)
print(out)
