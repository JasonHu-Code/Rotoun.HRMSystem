# Rotoun HRMS · 前端

基于 **plus-ui 5.X（5.6.2-2.6.2）**（MIT License），Vue 3 + TypeScript + Element Plus + Vite。

| 项 | 版本 |
|---|---|
| Vue | 3.5.30 |
| Element Plus | 2.13.5 |
| Vite | 7.3.2 |
| Node | >= 20.19 |
| 包管理 | pnpm 10 |

## 启动

```bash
pnpm install
pnpm dev
```

默认端口 `80`（见 `.env.development` 的 `VITE_APP_PORT`，Windows 下可改为 8081）。

开发环境通过 Vite 代理把 `/dev-api` 转发到后端 `http://localhost:8080`，配置见 `vite.config.ts` 与 `.env.development`。

## 目录

```
src/api/         接口
src/views/       页面
src/components/  组件
src/layout/      布局
src/utils/       工具（rotoun.ts 为通用工具）
src/store/       Pinia
```
