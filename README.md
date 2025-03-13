# ReplayKit
### 基于本地socket，实现的一个关于通过 ReplayKit 组件向宿主app传递 CMSampleBuffer 数据的工具包，包含视频与与音频。
### 使用方法，
  - 运行项目，将生成的 framework 导入工程。
  - 组件中使用 CYSampleHandlerSocketManager 发送，宿主app通过 CYSampleHandlerClientSocketManager 接收。
