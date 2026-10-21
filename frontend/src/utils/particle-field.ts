/**
 * 登录页背景粒子场（canvas）
 *
 * 为什么不用 CSS：CSS 背景网格只能整层位移，无法让单个粒子各自运动，更不可能响应鼠标位置。
 * 这里把每个粒子当成独立对象，才能做到"方块自转 + 向鼠标聚集环绕 + 鼠标柔光跟随"。
 *
 * 运动的两个分量是分开的，这是关键：
 *   - 漂移分量（dx/dy + 摆动）恒定，保证鼠标不动、移开时背景依然是活的
 *   - 交互分量（ivx/ivy）由鼠标产生并持续衰减到 0，所以追随是"被牵引"而非"被钉死"
 *
 * 无光标时的"无规则飘散"靠三层叠加，缺一层都会显得规律：
 *   1. 每颗粒子的初始方向是全圆随机、速度各不相同 —— 打破"整体同向"
 *   2. 低频摆动相位（x/y 用不同频率）让轨迹是曲线而非直线 —— 打破"匀速直线"
 *   3. 明暗呼吸相位随机 —— 打破"整屏亮度一致"
 */

interface Particle {
  x: number;
  y: number;
  /** 自由漂移速度（由随机方向 + 随机速度生成，恒定） */
  dx: number;
  dy: number;
  /** 鼠标交互产生的速度分量（每帧衰减） */
  ivx: number;
  ivy: number;
  /** 低频摆动：相位 / 相位推进速度 / 摆动幅度 */
  phase: number;
  phaseSpeed: number;
  amp: number;
  /** 明暗呼吸：相位 / 推进速度 */
  twinkle: number;
  twinkleSpeed: number;
  size: number;
  alpha: number;
  /** true = 方块（带自转），false = 圆点 */
  square: boolean;
  angle: number;
  spin: number;
  color: string;
}

export interface ParticleFieldOptions {
  /** 每多少平方像素生成一个粒子，越小越密 */
  density?: number;
  maxCount?: number;
  /** 鼠标影响半径（px） */
  influence?: number;
  /** 粒子间连线阈值（px） */
  linkDistance?: number;
}

const DEFAULTS: Required<ParticleFieldOptions> = {
  // 每 10500 平方像素一颗粒子、上限 178：比原来的 130 多约三成，
  // 肉眼能感到"更满"但还不会糊成一片（再往上连线会织成网，反而抢主体）
  density: 10500,
  maxCount: 178,
  influence: 190,
  linkDistance: 98
};

// 白色为主，少量呼应品牌橙，避免整屏花掉
const COLORS = ['255, 255, 255', '255, 255, 255', '255, 255, 255', '186, 222, 255', '255, 186, 128'];

export function createParticleField(canvas: HTMLCanvasElement, options: ParticleFieldOptions = {}) {
  const opts = { ...DEFAULTS, ...options };
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    return { destroy: () => {} };
  }

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let width = 0;
  let height = 0;
  let dpr = 1;
  let particles: Particle[] = [];
  let rafId = 0;

  // 鼠标用两个坐标：raw 是真实位置，soft 是插值后的绘制位置。
  // 插值让柔光和牵引力有"跟"的感觉，而不是瞬间跳过去。
  const pointer = { rawX: 0, rawY: 0, softX: 0, softY: 0, active: false };

  const rand = (min: number, max: number) => min + Math.random() * (max - min);

  const resize = () => {
    const rect = canvas.getBoundingClientRect();
    width = Math.max(1, rect.width);
    height = Math.max(1, rect.height);
    // DPR 封顶 2：4K 屏下按 3~4 倍渲染会让填充率翻数倍，而视觉收益几乎为 0
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    seed();
    // 重设 canvas.width 会清空画布；减弱动效模式下没有循环在跑，必须补画一帧，
    // 否则窗口一缩放就成了空背景
    if (reduceMotion) {
      draw();
    }
  };

  const seed = () => {
    const count = Math.min(opts.maxCount, Math.round((width * height) / opts.density));
    particles = Array.from({ length: count }, () => {
      // 方向全圆随机、速度各不相同：原来统一向上飘，看久了就是"一层布在挪"
      const dir = Math.random() * Math.PI * 2;
      const speed = rand(0.05, 0.2);
      return {
        x: Math.random() * width,
        y: Math.random() * height,
        dx: Math.cos(dir) * speed,
        dy: Math.sin(dir) * speed,
        ivx: 0,
        ivy: 0,
        phase: Math.random() * Math.PI * 2,
        phaseSpeed: rand(0.004, 0.016),
        amp: rand(0.05, 0.16),
        twinkle: Math.random() * Math.PI * 2,
        twinkleSpeed: rand(0.01, 0.035),
        size: rand(1, 2.6),
        alpha: rand(0.25, 0.72),
        square: Math.random() < 0.4,
        angle: Math.random() * Math.PI * 2,
        spin: rand(-0.012, 0.012),
        color: COLORS[Math.floor(Math.random() * COLORS.length)]
      };
    });
  };

  // 绘制与循环分开：减弱动效模式只需要画一帧，不能顺便把下一帧排上
  const draw = () => {
    ctx.clearRect(0, 0, width, height);

    // 柔光跟随：鼠标位置的呼吸光斑，是"追随"最直观的一层
    pointer.softX += (pointer.rawX - pointer.softX) * 0.12;
    pointer.softY += (pointer.rawY - pointer.softY) * 0.12;

    if (pointer.active) {
      const glow = ctx.createRadialGradient(pointer.softX, pointer.softY, 0, pointer.softX, pointer.softY, 210);
      glow.addColorStop(0, 'rgba(255, 255, 255, 0.2)');
      glow.addColorStop(0.45, 'rgba(170, 215, 255, 0.09)');
      glow.addColorStop(1, 'rgba(255, 255, 255, 0)');
      ctx.fillStyle = glow;
      ctx.fillRect(pointer.softX - 210, pointer.softY - 210, 420, 420);
    }

    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];

      if (pointer.active) {
        const dx = pointer.softX - p.x;
        const dy = pointer.softY - p.y;
        const dist = Math.hypot(dx, dy) || 1;

        if (dist < opts.influence) {
          const force = 1 - dist / opts.influence;
          const nx = dx / dist;
          const ny = dy / dist;
          // 径向：朝鼠标靠拢
          p.ivx += nx * force * 0.075;
          p.ivy += ny * force * 0.075;
          // 切向：绕鼠标打旋。只给径向会导致所有粒子塌缩成一个点，
          // 加一点垂直分量后它们会围绕鼠标流动，"追随"的观感就是这么来的
          p.ivx += -ny * force * 0.055;
          p.ivy += nx * force * 0.055;
        }
      }

      p.ivx *= 0.94;
      p.ivy *= 0.94;

      // 低频摆动：x/y 用不同频率（1.37 倍）才不会退化成一条斜线上的往返，
      // 叠在直线漂移上之后轨迹是缓慢游走的曲线，也就是"飘散"而不是"平移"
      p.phase += p.phaseSpeed;
      p.twinkle += p.twinkleSpeed;
      const swayX = Math.cos(p.phase) * p.amp;
      const swayY = Math.sin(p.phase * 1.37) * p.amp;

      p.x += p.dx + p.ivx + swayX;
      p.y += p.dy + p.ivy + swayY;
      if (p.square) {
        p.angle += p.spin;
      }

      // 出界环绕，保持粒子总数恒定
      if (p.x < -20) p.x = width + 20;
      if (p.x > width + 20) p.x = -20;
      if (p.y < -20) p.y = height + 20;
      if (p.y > height + 20) p.y = -20;

      // 明暗呼吸：每颗粒子有自己的相位，整屏亮度就不会是死板的一层
      let alpha = p.alpha + Math.sin(p.twinkle) * 0.16;
      if (alpha < 0.06) {
        alpha = 0.06;
      }
      // 越靠近鼠标越亮，强化"被牵引"的反馈
      if (pointer.active) {
        const d = Math.hypot(pointer.softX - p.x, pointer.softY - p.y);
        if (d < opts.influence) {
          alpha = Math.min(1, p.alpha + (1 - d / opts.influence) * 0.5);
        }
      }

      ctx.fillStyle = `rgba(${p.color}, ${alpha})`;
      if (p.square) {
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.angle);
        const s = p.size * 1.9;
        ctx.fillRect(-s / 2, -s / 2, s, s);
        ctx.restore();
      } else {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fill();
      }

      // 连线只向前配对，避免重复绘制
      for (let j = i + 1; j < particles.length; j++) {
        const q = particles[j];
        const dx = p.x - q.x;
        const dy = p.y - q.y;
        if (Math.abs(dx) > opts.linkDistance || Math.abs(dy) > opts.linkDistance) {
          continue;
        }
        const d = Math.hypot(dx, dy);
        if (d < opts.linkDistance) {
          // 粒子变多后连线数量是平方级增长，透明度相应下调，避免织成一张网
          ctx.strokeStyle = `rgba(255, 255, 255, ${(1 - d / opts.linkDistance) * 0.11})`;
          ctx.lineWidth = 0.6;
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(q.x, q.y);
          ctx.stroke();
        }
      }

      if (pointer.active) {
        const d = Math.hypot(pointer.softX - p.x, pointer.softY - p.y);
        if (d < opts.influence) {
          ctx.strokeStyle = `rgba(255, 255, 255, ${(1 - d / opts.influence) * 0.22})`;
          ctx.lineWidth = 0.7;
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(pointer.softX, pointer.softY);
          ctx.stroke();
        }
      }
    }
  };

  const loop = () => {
    draw();
    rafId = requestAnimationFrame(loop);
  };

  const onPointerMove = (e: PointerEvent) => {
    const rect = canvas.getBoundingClientRect();
    pointer.rawX = e.clientX - rect.left;
    pointer.rawY = e.clientY - rect.top;
    if (!pointer.active) {
      // 首次移动才激活：否则页面刚加载、鼠标还没进来时粒子会被中心点吸走
      pointer.softX = pointer.rawX;
      pointer.softY = pointer.rawY;
      pointer.active = true;
    }
  };

  // 鼠标移出窗口：撤销牵引，粒子靠衰减回到自由漂移
  const onPointerLeave = () => {
    pointer.active = false;
  };

  // 标签页切到后台时停帧：rAF 虽会被浏览器节流，但主动停更省电
  const onVisibility = () => {
    if (document.hidden) {
      cancelAnimationFrame(rafId);
      rafId = 0;
    } else if (!rafId && !reduceMotion) {
      rafId = requestAnimationFrame(loop);
    }
  };

  resize();
  window.addEventListener('resize', resize);

  if (reduceMotion) {
    // 尊重系统"减少动态效果"：只画一帧静态粒子，不启动循环、不响应鼠标
    draw();
    return {
      destroy: () => {
        window.removeEventListener('resize', resize);
      }
    };
  }

  window.addEventListener('pointermove', onPointerMove, { passive: true });
  window.addEventListener('pointerleave', onPointerLeave);
  document.addEventListener('visibilitychange', onVisibility);
  rafId = requestAnimationFrame(loop);

  return {
    destroy: () => {
      cancelAnimationFrame(rafId);
      window.removeEventListener('resize', resize);
      window.removeEventListener('pointermove', onPointerMove);
      window.removeEventListener('pointerleave', onPointerLeave);
      document.removeEventListener('visibilitychange', onVisibility);
    }
  };
}
