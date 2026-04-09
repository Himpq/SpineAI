# SpineAI
Private Healthcare Project, Spine Diagnosis

## Todo list

- 前端患者信息门户上传图片的进度条 is fake
- 医生端前端复核界面的图片阅览当分辨率较高缩放会有问题
- RemoteInferer当图片分辨率较高文本打印会很小
- 占位信息还没移除
- 盆骨锁骨模型混淆了(检测脚本检测为pelvis，但是能正常检测calvicle & T1，但是结果却是pelvis的结果)
- classify日志还未移除base64图片

- spine.healthit.cn的转发FUPT逻辑仍有问题:
   - 注册时同步资料无法正确转发(URL错误)
   - AI聊天时候streaming变为非streaming
