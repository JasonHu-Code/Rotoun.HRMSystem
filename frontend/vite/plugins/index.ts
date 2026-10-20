import vue from '@vitejs/plugin-vue';

import createUnoCss from './unocss';
import createAutoImport from './auto-import';
import createComponents from './components';
import createIcons from './icons';
import createSvgIconsPlugin from './svg-icon';
import createCompression from './compression';
import createSetupExtend from './setup-extend';
import path from 'path';

export default (viteEnv: any, isBuild = false): [] => {
  const vitePlugins: any = [];
  vitePlugins.push(vue());
  // 已移除 vite-plugin-vue-devtools：它只在开发态往 body 注入一个跟随鼠标的悬浮锚点
  // （#__vue-devtools-container__），会挡在登录页背景上，看着像页面自己的控件。
  // 该插件没有"保留能力只隐藏锚点"的配置项。需要调试时二选一：
  //   1) 把下面这行加回来：vitePlugins.push(vueDevTools());
  //   2) 用浏览器装 Vue DevTools 扩展
  // vitePlugins.push(vueDevTools());
  vitePlugins.push(createUnoCss());
  vitePlugins.push(createAutoImport(path));
  vitePlugins.push(createComponents(path));
  vitePlugins.push(createCompression(viteEnv));
  vitePlugins.push(createIcons());
  vitePlugins.push(createSvgIconsPlugin(path));
  vitePlugins.push(createSetupExtend());
  return vitePlugins;
};
