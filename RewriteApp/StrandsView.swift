import SwiftUI
import WebKit

/// The reactbits.dev "Strands" animation, rendered by its actual WebGL/GLSL
/// shader inside a `WKWebView`. The shader is run with raw WebGL2 (no `ogl`,
/// no CDN) so the page is fully self-contained and works offline. The live mic
/// `level` (0…1, from `SpeechManager`) is pushed into the page so the strands
/// intensify while the user talks.
struct StrandsView: NSViewRepresentable {
    /// reactbits props (hex colors + the knobs from the original component).
    var colors: [String] = ["#F97316", "#7C3AED", "#06B6D4"]
    var count: Int = 3
    var speed: Double = 0.5
    var amplitude: Double = 1
    var waviness: Double = 1
    var thickness: Double = 0.7
    var glow: Double = 2.6
    var taper: Double = 3
    var spread: Double = 1
    var hueShift: Double = 0
    var intensity: Double = 0.6
    var saturation: Double = 2
    var opacity: Double = 1
    var scale: Double = 1.5
    /// Smoothed mic amplitude 0…1. Pushed into the shader as a swell factor.
    var level: Float = 0

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.wantsLayer = true
        // Transparent web view + transparent page, so the strands (which fade to
        // nothing at the edges) float directly on the overlay background and
        // blend with the whole page — no visible card or border.
        web.setValue(false, forKey: "drawsBackground")
        web.loadHTMLString(Self.html(
            colors: colors, count: count, speed: speed, amplitude: amplitude,
            waviness: waviness, thickness: thickness, glow: glow, taper: taper,
            spread: spread, hueShift: hueShift, intensity: intensity,
            saturation: saturation, opacity: opacity, scale: scale), baseURL: nil)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let lvl = min(max(level, 0), 1)
        web.evaluateJavaScript("window.setLevel && window.setLevel(\(lvl));", completionHandler: nil)
    }

    // MARK: HTML / shader

    private static func jsonColors(_ colors: [String]) -> String {
        "[" + colors.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }

    private static func html(colors: [String], count: Int, speed: Double, amplitude: Double,
                             waviness: Double, thickness: Double, glow: Double, taper: Double,
                             spread: Double, hueShift: Double, intensity: Double,
                             saturation: Double, opacity: Double, scale: Double) -> String {
        """
        <!doctype html><html><head><meta charset='utf-8'>
        <style>
          html,body{margin:0;height:100%;overflow:hidden;background:transparent;}
          canvas{display:block;width:100vw;height:100vh;}
        </style></head>
        <body><canvas id='gl'></canvas>
        <script>
        const PROPS = {
          colors: \(jsonColors(colors)),
          count: \(count), speed: \(speed), amplitude: \(amplitude), waviness: \(waviness),
          thickness: \(thickness), glow: \(glow), taper: \(taper), spread: \(spread),
          hueShift: \(hueShift), intensity: \(intensity), saturation: \(saturation),
          opacity: \(opacity), scale: \(scale)
        };
        const VERT = `#version 300 es
        in vec2 position;
        void main(){ gl_Position = vec4(position, 0.0, 1.0); }`;
        const FRAG = `#version 300 es
        precision highp float;
        uniform float uTime;
        uniform vec2 uResolution;
        uniform vec3 uColors[8];
        uniform int uColorCount;
        uniform int uStrandCount;
        uniform float uSpeed;
        uniform float uAmplitude;
        uniform float uWaviness;
        uniform float uThickness;
        uniform float uGlow;
        uniform float uTaper;
        uniform float uSpread;
        uniform float uHueShift;
        uniform float uIntensity;
        uniform float uOpacity;
        uniform float uScale;
        uniform float uSaturation;
        out vec4 fragColor;
        const float PI = 3.14159265;
        vec3 spectrum(float t){ return 0.5 + 0.5 * cos(2.0 * PI * (t + vec3(0.00, 0.33, 0.67))); }
        vec3 samplePalette(float t){
          t = fract(t);
          float scaled = t * float(uColorCount);
          int idx = int(floor(scaled));
          float blend = fract(scaled);
          int nextIdx = idx + 1;
          if (nextIdx >= uColorCount) nextIdx = 0;
          return mix(uColors[idx], uColors[nextIdx], blend);
        }
        vec3 strandColor(float t){ if (uColorCount > 0) return samplePalette(t); return spectrum(t); }
        void main(){
          vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution) / uResolution.y;
          uv /= max(uScale, 0.0001);
          float e = 0.06 + uIntensity * 0.94;
          float env = pow(max(cos(uv.x * PI * 1.3), 0.0), uTaper);
          vec3 col = vec3(0.0);
          for (int i = 0; i < 12; i++){
            if (i >= uStrandCount) break;
            float fi = float(i);
            float ph = fi * 1.7 * uSpread;
            float freq = (2.0 + fi * 0.35) * uWaviness;
            float spd = 1.4 + fi * 1.2;
            float tt = uTime * uSpeed;
            float w = sin(uv.x * freq + tt * spd + ph) * 0.60
                    + sin(uv.x * freq * 1.1 - tt * spd * 0.7 + ph * 1.7) * 0.40;
            float amp = (0.1 + 0.02 * e) * env * uAmplitude;
            float y = w * amp;
            float d = abs(uv.y - y);
            float thick = (0.001 + 0.05 * e) * (0.35 + env) * uThickness;
            float g = thick / (d + thick * 0.45);
            g = g * g;
            float h = fi / float(uStrandCount) + uv.x * 0.30 + uTime * 0.04 + uHueShift;
            col += strandColor(h) * g * env;
          }
          col *= 0.45 + 0.7 * e;
          col = 1.0 - exp(-col * uGlow);
          float gray = dot(col, vec3(0.2126, 0.7152, 0.0722));
          col = max(mix(vec3(gray), col, uSaturation), 0.0);
          float lum = max(max(col.r, col.g), col.b);
          float alpha = clamp(lum, 0.0, 1.0) * uOpacity;
          fragColor = vec4(col * uOpacity, alpha);
        }`;
        function hexToRGB(h){
          h = h.replace('#','');
          if (h.length === 3) h = h.split('').map(c => c + c).join('');
          const n = parseInt(h, 16);
          return [((n>>16)&255)/255, ((n>>8)&255)/255, (n&255)/255];
        }
        function buildPalette(colors){
          const filled = (colors && colors.length) ? colors : ['#ffffff'];
          const out = [];
          for (let i = 0; i < 8; i++){ const hex = filled[i] ?? filled[filled.length-1]; out.push(...hexToRGB(hex)); }
          return new Float32Array(out);
        }
        const canvas = document.getElementById('gl');
        const gl = canvas.getContext('webgl2', { alpha: true, premultipliedAlpha: true, antialias: true });
        function compile(type, src){
          const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
          if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
          return s;
        }
        const prog = gl.createProgram();
        gl.attachShader(prog, compile(gl.VERTEX_SHADER, VERT));
        gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, FRAG));
        gl.linkProgram(prog);
        gl.useProgram(prog);
        const vao = gl.createVertexArray(); gl.bindVertexArray(vao);
        const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 3,-1, -1,3]), gl.STATIC_DRAW);
        const posLoc = gl.getAttribLocation(prog, 'position');
        gl.enableVertexAttribArray(posLoc); gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);
        gl.clearColor(0,0,0,0); gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        const U = n => gl.getUniformLocation(prog, n);
        const u = { time:U('uTime'), res:U('uResolution'), colors:U('uColors'), colorCount:U('uColorCount'),
          strandCount:U('uStrandCount'), speed:U('uSpeed'), amplitude:U('uAmplitude'), waviness:U('uWaviness'),
          thickness:U('uThickness'), glow:U('uGlow'), taper:U('uTaper'), spread:U('uSpread'),
          hueShift:U('uHueShift'), intensity:U('uIntensity'), opacity:U('uOpacity'), scale:U('uScale'),
          saturation:U('uSaturation') };
        const palette = buildPalette(PROPS.colors);
        const colorCount = Math.min(PROPS.colors.length, 8);
        const strandCount = Math.min(Math.max(Math.round(PROPS.count), 1), 12);
        function resize(){
          const dpr = Math.min(window.devicePixelRatio || 1, 2);
          const w = canvas.clientWidth || 1, h = canvas.clientHeight || 1;
          canvas.width = Math.max(1, Math.round(w*dpr)); canvas.height = Math.max(1, Math.round(h*dpr));
          gl.viewport(0, 0, canvas.width, canvas.height);
        }
        new ResizeObserver(resize).observe(canvas); resize();
        window.__level = 0;
        window.setLevel = v => { window.__level = Math.max(0, Math.min(1, +v || 0)); };
        function frame(ms){
          requestAnimationFrame(frame);
          const lvl = window.__level || 0;
          gl.useProgram(prog); gl.bindVertexArray(vao);
          gl.uniform1f(u.time, ms*0.001);
          gl.uniform2f(u.res, canvas.width, canvas.height);
          gl.uniform3fv(u.colors, palette);
          gl.uniform1i(u.colorCount, colorCount);
          gl.uniform1i(u.strandCount, strandCount);
          gl.uniform1f(u.speed, PROPS.speed * (1 + lvl*0.5));
          gl.uniform1f(u.amplitude, PROPS.amplitude * (1 + lvl*0.8));
          gl.uniform1f(u.waviness, PROPS.waviness);
          gl.uniform1f(u.thickness, PROPS.thickness);
          gl.uniform1f(u.glow, PROPS.glow * (1 + lvl*0.35));
          gl.uniform1f(u.taper, PROPS.taper);
          gl.uniform1f(u.spread, PROPS.spread);
          gl.uniform1f(u.hueShift, PROPS.hueShift);
          gl.uniform1f(u.intensity, Math.min(1, PROPS.intensity * (1 + lvl*0.6)));
          gl.uniform1f(u.opacity, PROPS.opacity);
          gl.uniform1f(u.scale, PROPS.scale);
          gl.uniform1f(u.saturation, PROPS.saturation);
          gl.clear(gl.COLOR_BUFFER_BIT);
          gl.drawArrays(gl.TRIANGLES, 0, 3);
        }
        requestAnimationFrame(frame);
        </script></body></html>
        """
    }
}
