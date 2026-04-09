document.addEventListener('DOMContentLoaded', () => {
  const fileInput     = document.getElementById('dicom3d-file');
  const openBtn       = document.getElementById('dicom3d-open-btn');
  const exampleBtn    = document.getElementById('dicom3d-example-btn');
  const dropZone      = document.getElementById('dicom3d-drop');
  const statusEl      = document.getElementById('dicom3d-status');
  const opacityInput  = document.getElementById('dicom3d-opacity');
  const lutSelect     = document.getElementById('dicom3d-lut');
  const showCurveChk  = document.getElementById('dicom3d-show-curve');
  const fileMetaEl    = document.getElementById('dicom3d-file-meta');
  const dimsEl        = document.getElementById('dicom3d-dims');
  const fpsEl         = document.getElementById('dicom3d-fps');
  const metricsBody   = document.getElementById('dicom3d-metrics-body');
  const metricsRefresh= document.getElementById('dicom3d-metrics-refresh');

  if (!fileInput) return; // page not present

  const viewports = {};
  let currentStack = null;
  let animationId = null;
  let frameCount = 0;
  let fpsTs = performance.now();
  const RENDER_SCALE = 0.9;          // 降低渲染分辨率减轻 GPU 负载
  const USTEP_HIGH = 128;            // 默认体渲染步数
  const USTEP_LOW = 80;              // 交互时临时降级步数
  let ustepRestoreTimer = null;

  const exampleUrl = '/api/dicom3d/example';

  function setStatus(msg, isError = false) {
    if (!statusEl) return;
    statusEl.textContent = msg;
    statusEl.style.borderColor = isError ? '#fca5a5' : '#e2e8f0';
    statusEl.style.color = isError ? '#ef4444' : '#475569';
    statusEl.style.background = '#fff';
  }

  function b64ToArrayBuffer(b64) {
    const bin = atob(b64);
    const len = bin.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
    return bytes.buffer;
  }

  function ensureAMI() {
    if (!window.AMI) {
      setStatus('AMI.js 未加载', true);
      return false;
    }
    return true;
  }

  function initViewport(name) {
    const container = document.getElementById(`dicom3d-viewport-${name}`);
    if (!container) return;
    const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: false });
    renderer.setPixelRatio(Math.min(1.5, (window.devicePixelRatio || 1) * RENDER_SCALE));
    renderer.setSize(container.clientWidth * RENDER_SCALE, container.clientHeight * RENDER_SCALE);
    renderer.setClearColor(0x0f172a, 1);
    container.appendChild(renderer.domElement);

    let camera;
    if (name === '3d') {
      camera = new THREE.PerspectiveCamera(45, container.clientWidth / container.clientHeight, 0.1, 4000);
    } else {
      const aspect = container.clientWidth / container.clientHeight || 1;
      camera = new THREE.OrthographicCamera(-1 * aspect, 1 * aspect, 1, -1, 0.1, 4000);
    }
    const controls = ensureAMI() ? new AMI.TrackballControl(camera, renderer.domElement) : null;
    if (controls) {
      controls.rotateSpeed = 3.0;
      controls.zoomSpeed = 2.0;
      controls.panSpeed = 1.5;
      controls.staticMoving = true;
    }

    viewports[name] = {
      container,
      renderer,
      camera,
      controls,
      scene: new THREE.Scene(),
      stackHelper: null,
      vrHelper: null,
      lutHelper: null,
      overlay: container.querySelector('.dicom3d-overlay'),
    };
  }

  function initViewports() {
    ['3d', 'axial', 'sagittal', 'coronal'].forEach(initViewport);
    window.addEventListener('resize', resizeViewports);
    renderLoop();
  }

  function resizeViewports() {
    Object.values(viewports).forEach((vp) => {
      if (!vp.container || !vp.renderer || !vp.camera) return;
      const w = (vp.container.clientWidth || 10) * RENDER_SCALE;
      const h = (vp.container.clientHeight || 10) * RENDER_SCALE;
      vp.renderer.setSize(w, h);
      if (vp.camera.isPerspectiveCamera) {
        vp.camera.aspect = w / h;
      } else {
        const aspect = w / h;
        const dims = vp.stackHelper?.dimensionsIJK;
        const scale = dims
          ? Math.max(dims.x || 1, dims.y || 1, dims.z || 1)
          : 1;
        vp.camera.left = -scale * aspect;
        vp.camera.right = scale * aspect;
        vp.camera.top = scale;
        vp.camera.bottom = -scale;
      }
      vp.camera.updateProjectionMatrix();
    });
  }

  function renderLoop() {
    animationId = requestAnimationFrame(renderLoop);
    const page = document.getElementById('page-dicom3d');
    const active = page && page.classList.contains('active-view');
    if (!active) return; // 页签未激活时跳过渲染，释放 GPU
    Object.values(viewports).forEach((vp) => {
      if (!vp.renderer || !vp.scene || !vp.camera) return;
      if (vp.controls) vp.controls.update();
      vp.renderer.render(vp.scene, vp.camera);
    });
    frameCount += 1;
    const now = performance.now();
    if (now - fpsTs >= 1000 && fpsEl) {
      const fps = Math.round((frameCount * 1000) / (now - fpsTs));
      fpsEl.textContent = `FPS ${fps}`;
      fpsTs = now;
      frameCount = 0;
    }
  }

  async function loadExample() {
    if (!ensureAMI()) return;
    try {
      setStatus('从远程获取示例体...');
      const resp = await fetch(exampleUrl);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const data = await resp.json();
      if (data.status !== 'ok' || !data.file_base64) throw new Error(data.message || '远程返回异常');
      const buffer = b64ToArrayBuffer(data.file_base64);
      await loadBuffer(buffer, data.filename || 'demo.nii.gz');
      if (fileMetaEl) fileMetaEl.textContent = data.filename || 'demo.nii.gz';
    } catch (e) {
      setStatus(`示例加载失败: ${e.message}`, true);
    }
  }

  async function loadBuffer(buffer, filename = 'volume.nii.gz') {
    if (!ensureAMI()) return;
    setStatus('解析体数据...');
    const loader = new AMI.VolumeLoader(viewports['3d']?.container || document.body);
    try {
      const parsed = await loader.parse({ url: filename, buffer });
      loader._data.push(parsed);
      if (!loader.data.length) throw new Error('未解析到有效序列');
      const series = loader.data[0].mergeSeries(loader.data)[0];
      currentStack = series.stack[0];
      loader.free();
      createVisualizations(currentStack);
      renderMetrics(generateMockMetrics(currentStack));
      setStatus('加载完成');
      if (dimsEl && currentStack.dimensionsIJK) {
        const d = currentStack.dimensionsIJK;
        dimsEl.textContent = `${d.x} × ${d.y} × ${d.z}`;
      }
    } catch (err) {
      setStatus(`解析失败: ${err.message}`, true);
    }
  }

  function clearSceneObjects(vp) {
    if (!vp || !vp.scene) return;
    while (vp.scene.children.length > 0) vp.scene.remove(vp.scene.children[0]);
  }

  function create3DVolume(stack) {
    const vp = viewports['3d'];
    if (!vp) return;
    clearSceneObjects(vp);

    const vrHelper = new AMI.VolumeRenderingHelper(stack);
    vp.scene.add(vrHelper);
    vp.vrHelper = vrHelper;

    const lutHelper = new AMI.LutHelper('dicom3d-lut-canvases');
    lutHelper.luts = AMI.LutHelper.presetLuts();
    lutHelper.lut = lutSelect ? lutSelect.value : 'random';
    const ww = (stack.minMax && stack.minMax.length === 2) ? (stack.minMax[1] - stack.minMax[0]) : 350;
    const wc = (stack.minMax && stack.minMax.length === 2) ? ((stack.minMax[1] + stack.minMax[0]) / 2) : 40;

    const setUniform = (name, val) => {
      if (vrHelper.uniforms && vrHelper.uniforms[name]) {
        vrHelper.uniforms[name].value = val;
      }
    };

    setUniform('uTextureLUT', lutHelper.texture);
    setUniform('uLut', 1);
    setUniform('uAlphaCorrection', (opacityInput ? opacityInput.value : 65) / 100);
    setUniform('uSteps', USTEP_HIGH);
    setUniform('uWindowCenter', wc);
    setUniform('uWindowWidth', ww);
    vp.lutHelper = lutHelper;

    const center = stack.worldCenter();
    vp.camera.position.set(center.x - stack.dimensionsIJK.x, center.y - stack.dimensionsIJK.y, center.z + stack.dimensionsIJK.z * 1.5);
    vp.camera.lookAt(center.x, center.y, center.z);
    if (vp.controls) {
      vp.controls.target.set(center.x, center.y, center.z);
      vp.controls.update();
    }

    const ambient = new THREE.AmbientLight(0xffffff, 0.7);
    const dir = new THREE.DirectionalLight(0xffffff, 0.6);
    dir.position.set(1, 1, 1);
    vp.scene.add(ambient);
    vp.scene.add(dir);
  }

  function createSliceView(name, orientation) {
    const vp = viewports[name];
    if (!vp || !currentStack) return;
    clearSceneObjects(vp);

    const helper = new AMI.StackHelper(currentStack);
    helper.bbox.visible = false;
    helper.border.color = orientation === 2 ? 0xff1744 : orientation === 0 ? 0x00e676 : 0x00b0ff;
    helper.orientation = orientation;
    helper.index = Math.floor(helper.orientationMaxIndex / 2);
    if (currentStack.minMax && currentStack.minMax.length === 2) {
      helper.windowCenter = (currentStack.minMax[0] + currentStack.minMax[1]) / 2;
      helper.windowWidth = currentStack.minMax[1] - currentStack.minMax[0];
    } else if ('intensityAuto' in helper) {
      helper.intensityAuto = true;
    }
    if (helper.slice) {
      helper.slice.interpolation = 1;
      helper.slice.canvasWidth = vp.renderer.domElement.width;
      helper.slice.canvasHeight = vp.renderer.domElement.height;
    }
    vp.scene.add(helper);
    vp.stackHelper = helper;

    const center = currentStack.worldCenter();
    const bbox = currentStack.worldBoundingBox();
    const sizeX = bbox[1] - bbox[0];
    const sizeY = bbox[3] - bbox[2];
    const sizeZ = bbox[5] - bbox[4];
    const maxDim = Math.max(sizeX, sizeY, sizeZ);
    const distance = maxDim * 1.2;
    vp.camera.position.set(center.x, center.y, center.z);
    if (orientation === 2) {
      vp.camera.position.z = center.z + distance;
      vp.camera.up.set(0, -1, 0);
    } else if (orientation === 0) {
      vp.camera.position.x = center.x - distance;
      vp.camera.up.set(0, 0, 1);
    } else {
      vp.camera.position.y = center.y + distance;
      vp.camera.up.set(0, 0, 1);
    }
    vp.camera.lookAt(center.x, center.y, center.z);
    if (vp.camera.isOrthographicCamera) {
      const aspect = (vp.container.clientWidth || 1) / (vp.container.clientHeight || 1);
      vp.camera.left = -maxDim * aspect;
      vp.camera.right = maxDim * aspect;
      vp.camera.top = maxDim;
      vp.camera.bottom = -maxDim;
      vp.camera.near = 0.1;
      vp.camera.far = distance * 10;
      vp.camera.updateProjectionMatrix();
    }
    if (vp.controls) {
      vp.controls.target.set(center.x, center.y, center.z);
      vp.controls.update();
    }

    const overlay = vp.overlay;
    const updateInfo = () => {
      if (overlay) overlay.textContent = `切片 ${helper.index + 1} / ${helper.orientationMaxIndex + 1}`;
    };
    updateInfo();
    if (helper.slice && helper.slice.mesh) helper.slice.mesh.visible = true;

    const container = vp.container;
    let wheelRAF = false;
    container.addEventListener('wheel', (e) => {
      e.preventDefault();
      if (wheelRAF) return;
      wheelRAF = true;
      requestAnimationFrame(() => {
        if (e.deltaY > 0) helper.index = Math.min(helper.index + 1, helper.orientationMaxIndex);
        else helper.index = Math.max(helper.index - 1, 0);
        updateInfo();
        wheelRAF = false;
      });
      // 降级体渲染步数，滚轮停止后再恢复
      knockDownUSteps();
    }, { passive: false });
    container.addEventListener('dblclick', () => {
      helper.index = Math.floor(helper.orientationMaxIndex / 2);
      updateInfo();
    });

    // 强制渲染一次，避免初始空白
    if (vp.renderer && vp.scene && vp.camera) {
      vp.renderer.render(vp.scene, vp.camera);
    }
  }

  function createSliceViews(stack) {
    createSliceView('axial', 2);
    createSliceView('sagittal', 0);
    createSliceView('coronal', 1);
  }

  function buildMockCenters(stack) {
    if (!stack) return [];
    const center = stack.worldCenter();
    const bbox = stack.worldBoundingBox();
    const sizeZ = bbox[5] - bbox[4];
    const vertebrae = 10;
    const points = [];
    for (let i = 0; i < vertebrae; i++) {
      const t = i / (vertebrae - 1);
      const z = center.z - sizeZ * 0.4 + sizeZ * 0.8 * t;
      const curve = Math.sin(t * Math.PI) * (20 / vertebrae);
      points.push({ x: center.x + curve, y: center.y, z, label: `V${i + 1}` });
    }
    return points;
  }

  function drawSpineCurve(centers) {
    const vp = viewports['3d'];
    if (!vp || !centers.length) return;
    // remove old
    ['dicom3d-spine-line', 'dicom3d-spine-nodes'].forEach((name) => {
      const obj = vp.scene.getObjectByName(name);
      if (obj) vp.scene.remove(obj);
    });
    const pts = centers.map((c) => new THREE.Vector3(c.x, c.y, c.z));
    const lineGeo = new THREE.BufferGeometry().setFromPoints(pts);
    const lineMat = new THREE.LineBasicMaterial({ color: 0x00d4ff, linewidth: 2, transparent: true, opacity: 0.9 });
    const line = new THREE.Line(lineGeo, lineMat);
    line.name = 'dicom3d-spine-line';
    vp.scene.add(line);

    const group = new THREE.Group();
    group.name = 'dicom3d-spine-nodes';
    pts.forEach((p) => {
      const g = new THREE.SphereGeometry(1.8, 12, 12);
      const m = new THREE.MeshBasicMaterial({ color: 0xff6b6b, opacity: 0.85, transparent: true });
      const mesh = new THREE.Mesh(g, m);
      mesh.position.copy(p);
      group.add(mesh);
    });
    vp.scene.add(group);
  }

  function toggleCurve(show) {
    const vp = viewports['3d'];
    if (!vp) return;
    ['dicom3d-spine-line', 'dicom3d-spine-nodes'].forEach((name) => {
      const obj = vp.scene.getObjectByName(name);
      if (obj) obj.visible = show;
    });
  }

  function createVisualizations(stack) {
    create3DVolume(stack);
    createSliceViews(stack);
    const centers = buildMockCenters(stack);
    drawSpineCurve(centers);
    if (showCurveChk) toggleCurve(showCurveChk.checked);
    Object.values(viewports).forEach((vp) => {
      if (vp.overlay) vp.overlay.textContent = '';
    });
  }

  function generateMockMetrics(stack) {
    const dims = stack?.dimensionsIJK || { x: 256, y: 256, z: 128 };
    const cobb = 10 + (dims.z % 25);           // 10-34
    const lord = 40 + (dims.x % 15);           // 40-54
    const kyph = 25 + (dims.y % 20);           // 25-44
    const curvature = (cobb * 1.2).toFixed(1);
    const turnPerSeg = (cobb / 8).toFixed(1);
    const severity = cobb < 20 ? '轻度' : cobb < 35 ? '中度' : '重度';
    return {
      cobb,
      lord,
      kyph,
      curvature,
      turnPerSeg,
      severity,
      note: '示例参数，真实测量需算法推理。'
    };
  }

  function renderMetrics(data) {
    if (!metricsBody || !data) return;
    metricsBody.innerHTML = `
      <div class="dicom3d-metric">
        <h4>Cobb角</h4>
        <div class="value">${data.cobb.toFixed(1)}°</div>
        <div class="note">${data.severity} | 10-40°为常见范围</div>
      </div>
      <div class="dicom3d-metric">
        <h4>腰椎前凸 (Lordosis)</h4>
        <div class="value">${data.lord.toFixed(1)}°</div>
        <div class="note">参考: 40-60°</div>
      </div>
      <div class="dicom3d-metric">
        <h4>胸椎后凸 (Kyphosis)</h4>
        <div class="value">${data.kyph.toFixed(1)}°</div>
        <div class="note">参考: 20-45°</div>
      </div>
      <div class="dicom3d-metric">
        <h4>总曲率</h4>
        <div class="value">${data.curvature}°</div>
        <div class="note">示例值，未做真实测量</div>
      </div>
      <div class="dicom3d-metric">
        <h4>分段曲率</h4>
        <div class="value">${data.turnPerSeg}°/seg</div>
        <div class="note">越高表示弯曲越集中</div>
      </div>
      <div class="dicom3d-metric">
        <h4>提示</h4>
        <div class="note">${data.note}</div>
      </div>
    `;
  }

  // 将体渲染步长暂时降低，延时恢复
  function knockDownUSteps() {
    const vr = viewports['3d']?.vrHelper;
    if (!vr) return;
    vr.uniforms.uSteps.value = USTEP_LOW;
    if (ustepRestoreTimer) clearTimeout(ustepRestoreTimer);
    ustepRestoreTimer = setTimeout(() => {
      vr.uniforms.uSteps.value = USTEP_HIGH;
    }, 400);
  }

  // 当用户拖拽/旋转 3D 视图时也触发降级
  ['mousedown', 'touchstart'].forEach(evt => {
    const c = document.getElementById('dicom3d-viewport-3d');
    if (c) c.addEventListener(evt, knockDownUSteps, { passive: true });
  });

  function handleFile(file) {
    if (!file) return;
    if (fileMetaEl) fileMetaEl.textContent = `${file.name} (${(file.size / 1024 / 1024).toFixed(2)} MB)`;
    const reader = new FileReader();
    reader.onload = (e) => {
      loadBuffer(e.target.result, file.name);
    };
    reader.readAsArrayBuffer(file);
    setStatus('读取文件...');
  }

  // events
  if (openBtn) openBtn.addEventListener('click', () => fileInput.click());
  if (fileInput) fileInput.addEventListener('change', (e) => handleFile(e.target.files?.[0]));
  if (dropZone) {
    dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.style.borderColor = '#3b82f6'; });
    dropZone.addEventListener('dragleave', () => { dropZone.style.borderColor = '#cbd5e1'; });
    dropZone.addEventListener('drop', (e) => {
      e.preventDefault();
      dropZone.style.borderColor = '#cbd5e1';
      const file = e.dataTransfer?.files?.[0];
      handleFile(file);
    });
  }
  if (exampleBtn) exampleBtn.addEventListener('click', () => loadExample());
  if (opacityInput) opacityInput.addEventListener('input', (e) => {
    const val = e.target.value / 100;
    if (viewports['3d']?.vrHelper) viewports['3d'].vrHelper.uniforms.uAlphaCorrection.value = val;
  });
  if (lutSelect) lutSelect.addEventListener('change', (e) => {
    const lut = e.target.value;
    const vp = viewports['3d'];
    if (vp?.lutHelper && vp?.vrHelper) {
      vp.lutHelper.lut = lut;
      vp.vrHelper.uniforms.uTextureLUT.value = vp.lutHelper.texture;
    }
  });
  if (showCurveChk) showCurveChk.addEventListener('change', (e) => toggleCurve(e.target.checked));
  if (metricsRefresh) metricsRefresh.addEventListener('click', () => renderMetrics(generateMockMetrics(currentStack)));

  initViewports();
});
