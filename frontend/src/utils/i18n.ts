// translate router.meta.title, be used in breadcrumb sidebar tagsview
import i18n from '@/lang/index';

/**
 * 扁平字典翻译：以中文原文为 key。
 *
 * 为什么不用 `t('system.user.col.userName')` 这种结构化 key：
 * 业务页面里待翻译文案有 800+ 条，且大量是带标点的整句（"是否确认删除用户编号为"），
 * 逐条起结构化 key 的维护成本远高于收益，还容易在新增页面时漏键。
 * 以中文原文作 key 的好处是源码保持可读、脚本可批量接入、翻译表一眼能对。
 *
 * 中文串常含 "." "：" 等字符，vue-i18n 会把 "." 解析成嵌套路径，所以这里不走
 * t()，直接用 getLocaleMessage 取字典对象索引，彻底绕开 key 解析规则。
 */
export const tt = (zh: string): string => {
  if (!zh) {
    return '';
  }
  // 中文环境直接返回原文：省一次查表，也保证中文侧永远不会出现"缺词条的英文"
  const locale = String((i18n.global.locale as unknown as { value: string }).value || '');
  if (!locale || locale.startsWith('zh')) {
    return zh;
  }
  const dict = (i18n.global.getLocaleMessage(locale) as any)?.ui as Record<string, string> | undefined;
  return dict?.[zh] ?? zh;
};

/**
 * 带变量的扁平字典翻译。
 *
 * 中文原文里的插值无法整体做一个 key（变量值每次不同），所以把变量位置写成 {0} {1}，
 * 翻译表里也只保留一个带占位符的条目，翻译完再回填变量。
 * 例：ttf('上传文件大小不能超过 {0} MB!', 5) → 'File size cannot exceed 5 MB!'
 *
 * @param zh 带 {n} 占位符的中文模板
 * @param args 依次回填的变量
 */
export const ttf = (zh: string, ...args: (string | number)[]): string => {
  return tt(zh).replace(/\{(\d+)\}/g, (raw, idx: string) => {
    const val = args[Number(idx)];
    return val === undefined || val === null ? raw : String(val);
  });
};

/**
 * 获取国际化路由，如果不存在则原生返回
 * 路由标题来自数据库 sys_menu.menu_name，先查 route 命名空间（历史 key），
 * 再回落到扁平字典，这样新增菜单只需在翻译表里加一行中文 → 英文。
 * @param title 路由名称
 * @returns {string}
 */
export const translateRouteTitle = (title?: string): string => {
  if (!title) {
    return '';
  }
  const hasKey = i18n.global.te('route.' + title);
  if (hasKey) {
    return i18n.global.t('route.' + title);
  }
  return tt(title);
};
