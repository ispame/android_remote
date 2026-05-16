# pip install qrcode[pil]

import qrcode

uri = "openclaw://connect?gateway=wss%3A%2F%2Fboson-tech.top%2Fws&agentId=bk_ecdf8671f9f4fc7d&token=e29b35cb6d3f6c222b46c288eb763aa2&platform=openclaw&label=OpenClaw"

# 创建二维码
qr = qrcode.QRCode(
    version=1,
    error_correction=qrcode.constants.ERROR_CORRECT_M,
    box_size=10,
    border=4,
)

qr.add_data(uri)
qr.make(fit=True)

# 生成图片
img = qr.make_image(fill_color="black", back_color="white")

# 保存
img.save("openclaw_qrcode.png")

# 显示
img.show()

print("二维码已生成: openclaw_qrcode.png")