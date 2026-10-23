/**
 * 中文 → 英文扁平字典（第 4 批：浏览器实测后补齐的漏网词条）
 *
 * 收录范围：日期区间占位符、错误页、监控缓存/操作日志、富文本工具栏、
 * 上传校验（含 {n} 变量模板）、表单校验提示。
 */
export default {
  // ---- 日期区间（el-date-picker 的 start/end-placeholder 原先硬编码中文）----
  开始日期: 'Start date',
  结束日期: 'End date',

  // ---- 错误页 401 / 404 ----
  '401错误!': '401 Error!',
  '您没有访问权限！': 'You do not have access permission!',
  '对不起，您没有访问权限，请不要进行非法操作！您可以返回主页面': 'Sorry, you do not have access permission. Please do not perform illegal operations. You can return to the home page.',
  回首页: 'Back to Home',
  '404错误!': '404 Error!',
  '对不起，您正在寻找的页面不存在。尝试检查URL的错误，然后按浏览器上的刷新按钮或尝试在我们的应用程序中找到其他内容。':
    'Sorry, the page you are looking for does not exist. Please check the URL for errors, then refresh the page or look for something else in the application.',
  返回首页: 'Back to Home',
  '找不到网页！': 'Page not found!',

  // ---- 监控：缓存监控 ----
  单机: 'Standalone',
  集群: 'Cluster',
  禁用: 'Disable',

  // ---- 监控：操作日志 ----
  毫秒: 'ms',

  // ---- 富文本编辑器工具栏 ----
  '图片格式错误!': 'Invalid image format!',
  '请输入链接地址:': 'Please enter the link URL:',
  '请输入视频地址:': 'Please enter the video URL:',
  保存: 'Save',
  文本: 'Text',
  标题1: 'Heading 1',
  标题2: 'Heading 2',
  标题3: 'Heading 3',
  标题4: 'Heading 4',
  标题5: 'Heading 5',
  标题6: 'Heading 6',
  标准字体: 'Sans Serif',
  衬线字体: 'Serif',
  等宽字体: 'Monospace',

  // ---- 上传校验（{n} 为运行时变量，配合 ttf() 使用）----
  '上传文件大小不能超过 {0} MB!': 'File size cannot exceed {0} MB!',
  '上传文件数量不能超过 {0} 个!': 'The number of files cannot exceed {0}!',
  '文件格式不正确, 请上传 {0} 格式文件!': 'Invalid file format, please upload a {0} file!',
  '文件格式不正确, 请上传 {0} 图片格式文件!': 'Invalid file format, please upload a {0} image file!',
  '上传头像图片大小不能超过 {0} MB!': 'Avatar image size cannot exceed {0} MB!',

  // ---- 表单校验 ----
  "不能包含非法字符：< > \" ' \\ |": 'Illegal characters are not allowed: < > " \' \\ |',

  // ---- 菜单表单提示 ----
  '访问路由的默认传递参数，如：`{"id": 1, "name": "ry"}`': 'Default route parameters, e.g. `{"id": 1, "name": "ry"}`',

  // ---- 通用提示 ----
  系统提示: 'System Message',
  // 个人中心是静态路由，标题不走数据库，面包屑要单独查表
  个人中心: 'Personal Center',

  // ---- 请求层（utils/request.ts）：拦截器里的提示都在 toast 上直接可见 ----
  '数据正在处理，请勿重复提交': 'This data is being processed, please do not submit again',
  '登录状态已过期，您可以继续留在该页面，或者重新登录': 'Your login has expired. You can stay on this page or log in again.',
  重新登录: 'Log in again',
  '无效的会话，或者会话已过期，请重新登录。': 'Invalid session or the session has expired, please log in again.',
  后端接口连接异常: 'Backend API connection error',
  系统接口请求超时: 'API request timed out',
  // 这两条用于拼 "系统接口 + 状态码 + 异常"，英文侧同位置需要补空格
  系统接口: 'API ',
  异常: ' error',
  '正在下载数据，请稍候': 'Downloading data, please wait',
  '下载文件出现错误，请联系管理员！': 'Error downloading the file, please contact the administrator!',

  // ---- 后端错误码兜底文案（utils/errorCode.ts）----
  '认证失败，无法访问系统资源': 'Authentication failed, cannot access system resources',
  当前操作没有权限: 'You do not have permission for this operation',
  访问资源不存在: 'The requested resource does not exist',
  '系统未知错误，请反馈给管理员': 'Unknown system error, please report to the administrator',

  // ---- 相对时间（utils/index.ts）----
  刚刚: 'Just now',
  分钟前: ' min ago',
  小时前: ' hour(s) ago',
  '1天前': '1 day ago',
  // 中文时间拼串（10月20日20时30分）在英文侧换成 10/20/20:30
  月: '/',
  日: '/',
  时: ':',
  分: '',

  // ---- 字典数据标签（sys_dict_data.dict_label，DB 来源，由 useDict 统一翻译）----
  'PC': 'PC',
  'iOS': 'iOS',
  安卓: 'Android',
  小程序: 'Mini Program',
  三方登录认证: 'Third-party Login',
  密码认证: 'Password Auth',
  短信认证: 'SMS Auth',
  邮件认证: 'Email Auth',
  小程序认证: 'Mini Program Auth',
  授权: 'Authorize',
  其他: 'Other',
  显示: 'Show',
  隐藏: 'Hide',
  未知: 'Unknown',
  清空数据: 'Clear Data',
  通知: 'Notification',
  // ===== 数据权限（组织维度） =====
  '数据权限（组织）': 'Data Scope (Org)',
  '权限范围': 'Scope',
  '范围对象': 'Target',
  '可导出': 'Exportable',
  '全量': 'All',
  '本公司': 'Own company',
  '组织及子树': 'Org & subtree',
  '本组织': 'Own org',
  '仅本人': 'Self only',
  '选择法人': 'Select company',
  '选择组织': 'Select organization',
  '组织架构尚未导入': 'Org tree not imported yet',
  '无需选择': 'Not required',
  '选填': 'Optional',
  '添加一条范围': 'Add rule',
  '请为每一行选择范围对象': 'Please choose a target for every rule',
  '保存成功': 'Saved successfully',
  '规则取并集：多条规则时，能看到任一条范围内的数据；没有任何规则则该角色看不到业务数据。':
    'Rules are combined with OR. A role with no rules cannot see any business data.',
  '「全量」已包含所有数据，不能与其他范围同时配置；配了全量的角色不需要再加其它规则。':
    '"All" already covers every record and cannot be combined with other scopes.',
  '「全量」已包含所有数据，不能与其他范围同时配置': '"All" already covers every record and cannot be combined with other scopes',

};
