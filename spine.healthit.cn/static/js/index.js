document.addEventListener('DOMContentLoaded', () => {
  // DOM refs
  const dropZone     = document.getElementById('drop-zone');
  const fileInput    = document.getElementById('file-input');
  const resultImg    = document.getElementById('result-img');
  const resultCanvas = document.querySelector('.result-canvas');
  const emptyState   = document.getElementById('empty-placeholder');
  const loading      = document.getElementById('loading');
  const errorOverlay = document.getElementById('error-overlay');
  const errorMsg     = document.getElementById('error-msg');
  const confInput    = document.getElementById('conf-input');
  const confDisplay  = document.getElementById('conf-display');
  const chatLog      = document.getElementById('chat-log');
  const chatText     = document.getElementById('chat-text');
  const chatSend     = document.getElementById('chat-send');
  const chatMask     = document.getElementById('chat-mask');
  const chatPanel    = document.getElementById('chat-panel');
  const thyroidFileInput = document.getElementById('thyroid-file');
  const thyroidUploadBtn = document.getElementById('thyroid-upload-btn');
  const thyroidExampleBtn = document.getElementById('thyroid-example-btn');
  const thyroidRunBtn = document.getElementById('thyroid-run-btn');
  const thyroidPreview = document.getElementById('thyroid-preview');
  const thyroidResultImg = document.getElementById('thyroid-result-img');
  const thyroidPlaceholder = document.getElementById('thyroid-placeholder');
  const thyroidStatusBar = document.getElementById('thyroid-status-bar');
  const thyroidMeta = document.getElementById('thyroid-meta');
  const thyroidModel = document.getElementById('thyroid-model');
  const statusText   = document.getElementById('status-text');
  const statusSub    = document.getElementById('status-sub');
  const statusLatency = document.getElementById('status-latency');
  const statusUpdated = document.getElementById('status-updated');
  const statusCpu     = document.getElementById('status-cpu');
  const statusRam     = document.getElementById('status-ram');
  const statusRss     = document.getElementById('status-rss');
  const statusGpu     = document.getElementById('status-gpu');
  const statusGpuReserved = document.getElementById('status-gpu-reserved');
  const statusGpuCount = document.getElementById('status-gpu-count');
  const barCpu        = document.getElementById('bar-cpu');
  const barRam        = document.getElementById('bar-ram');
  const barGpu        = document.getElementById('bar-gpu');
  const chartCpu      = document.getElementById('status-chart-cpu');
  const chartRam      = document.getElementById('status-chart-ram');
  let currentModel   = 'l4l5';
  let detectionData  = null;
  let conversationHistory = [];
  let isChatEnabled = true;
  // zoom state
  let zScale = 1, zTx = 0, zTy = 0, zDragging = false, zLastX = 0, zLastY = 0;
  // Remote status is polled via /api/remote_metrics.
  const STATUS_INTERVAL_MS = 1000;
  let statusTimer = null;
  const cpuHistory = [];
  const ramHistory = [];
  let thyroidExampleB64 = null;

  function applyZoom() {
    if (!resultImg) return;
    resultImg.style.transform = `translate(-50%,-50%) translate(${zTx}px, ${zTy}px) scale(${zScale})`;
  }
  function resetZoom() {
    zScale = 1; zTx = 0; zTy = 0; applyZoom();
  }

  function formatGbFromMb(val) {
    if (val === undefined || val === null || Number.isNaN(val)) return '-';
    return `${(Number(val) / 1024).toFixed(2)} GB`;
  }

  function clampPercent(val) {
    if (val === undefined || val === null || Number.isNaN(val)) return 0;
    return Math.max(0, Math.min(100, Number(val)));
  }

  function setBar(el, percent) {
    if (!el) return;
    const p = clampPercent(percent);
    el.style.width = `${p}%`;
    el.style.background = p >= 85 ? '#ef4444' : p >= 60 ? '#f59e0b' : '#22c55e';
  }

  function pushHistory(arr, val, max = 60) {
    if (val === undefined || val === null || Number.isNaN(val)) return;
    arr.push(Number(val));
    if (arr.length > max) arr.shift();
  }

  // Thyroid demo helpers
  function thyroidStatusMsg(msg, isError = false) {
    if (thyroidStatusBar) {
      thyroidStatusBar.innerText = msg;
      thyroidStatusBar.style.color = isError ? '#ef4444' : '#475569';
      thyroidStatusBar.style.borderColor = isError ? '#fca5a5' : '#e2e8f0';
      thyroidStatusBar.style.background = '#fff';
    }
  }

  async function fileToBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const res = reader.result || '';
        resolve(res.toString().split(',').pop());
      };
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  }

  async function runThyroidInference() {
    if (!thyroidResultImg || !thyroidPlaceholder) return;
    try {
      const file = thyroidFileInput?.files?.[0];
      let b64 = null;
      if (file) {
        thyroidStatusMsg('正在读取上传图片...');
        b64 = await fileToBase64(file);
      } else if (thyroidExampleB64) {
        thyroidStatusMsg('正在读取示例图片...');
        b64 = thyroidExampleB64;
      } else {
        thyroidStatusMsg('请先上传图片或选择示例图', true);
        return;
      }
      thyroidPlaceholder.style.display = 'flex';
      thyroidResultImg.style.display = 'none';
      thyroidStatusMsg('正在调用模型推理...');
      const payload = {
        image_base64: b64,
        model_id: thyroidModel ? thyroidModel.value : 'swin-unet',
      };
      const resp = await fetch('/api/thyroid/infer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const data = await resp.json();
      if (data.status !== 'ok') throw new Error(data.message || '推理失败');
      if (data.image_base64) {
        thyroidResultImg.src = `data:${data.image_mimetype || 'image/png'};base64,${data.image_base64}`;
        thyroidResultImg.style.display = 'block';
        thyroidPlaceholder.style.display = 'none';
      }
      if (thyroidMeta) {
        thyroidMeta.innerText = `model: ${data.model_id || 'n/a'} | dice: ${data.dice ?? 'n/a'} | ${data.message || 'ok'}`;
      }
      thyroidStatusMsg('推理完成');
    } catch (err) {
      thyroidStatusMsg(`推理失败: ${err.message}`, true);
    }
  }
  function drawChart(canvas, data, color) {
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.clientWidth || 240;
    const h = canvas.clientHeight || 80;
    if (canvas.width !== w) canvas.width = w;
    if (canvas.height !== h) canvas.height = h;
    ctx.clearRect(0, 0, w, h);
    if (!data || data.length < 2) return;
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    const maxVal = 100;
    data.forEach((v, i) => {
      const x = (i / (data.length - 1)) * (w - 8) + 4;
      const y = h - (v / maxVal) * (h - 8) - 4;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }

  function updateStatusUI({ ok, latencyMs, viaProxy, data, error }) {
    if (!statusText) return;
    if (!ok) {
      statusText.innerText = '绂荤嚎';
      statusSub.innerText = '鏃犳硶杩炴帴';
      if (statusLatency) statusLatency.innerText = '- ms';
      if (statusUpdated) statusUpdated.innerText = new Date().toLocaleTimeString();
      return;
    }
    statusText.innerText = '鍦ㄧ嚎';
    statusSub.innerText = viaProxy ? '閫氳繃浜戠浠ｇ悊' : '鐩磋繛杩滅▼';
    if (statusLatency) statusLatency.innerText = `${latencyMs} ms`;
    if (statusUpdated) statusUpdated.innerText = new Date().toLocaleTimeString();
    if (statusCpu && data && data.cpu_percent !== undefined) statusCpu.innerText = `${data.cpu_percent}%`;
    if (statusRam && data && data.ram_used_mb !== undefined) {
      const total = data.ram_total_mb ? ` / ${(Number(data.ram_total_mb) / 1024).toFixed(2)} GB` : '';
      statusRam.innerText = `${(Number(data.ram_used_mb) / 1024).toFixed(2)} GB${total}`;
    }
    if (statusRss && data && data.process_rss_mb !== undefined) statusRss.innerText = formatGbFromMb(data.process_rss_mb);
    if (data) {
      setBar(barCpu, data.cpu_percent);
      setBar(barRam, data.ram_percent);
      const gpuPct = data.gpu_mem_reserved_mb ? (Number(data.gpu_mem_allocated_mb || 0) / Number(data.gpu_mem_reserved_mb || 1)) * 100 : 0;
      setBar(barGpu, gpuPct);
      pushHistory(cpuHistory, data.cpu_percent);
      pushHistory(ramHistory, data.ram_percent);
      drawChart(chartCpu, cpuHistory, '#3b82f6');
      drawChart(chartRam, ramHistory, '#22c55e');
    }
    if (data && data.cuda_available) {
      if (statusGpu) statusGpu.innerText = formatGbFromMb(data.gpu_mem_allocated_mb);
      if (statusGpuReserved) statusGpuReserved.innerText = formatGbFromMb(data.gpu_mem_reserved_mb);
      if (statusGpuCount) statusGpuCount.innerText = data.gpu_count ?? '-';
    } else {
      if (statusGpu) statusGpu.innerText = '-';
      if (statusGpuReserved) statusGpuReserved.innerText = '-';
      if (statusGpuCount) statusGpuCount.innerText = '0';
    }
  }

  async function fetchStatus() {
    if (!statusText) return;
    const start = performance.now();
    let data = null;
    try {
      const resp = await fetch('/api/remote_metrics', { cache: 'no-store' });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const proxy = await resp.json();
      data = proxy.metrics || proxy;
    } catch (err) {
      updateStatusUI({ ok: false, error: err.message });
      return;
    }
    const latencyMs = Math.round(performance.now() - start);
    updateStatusUI({ ok: true, latencyMs, viaProxy: true, data });
  }

  function isStatusVisible() {
    const el = document.getElementById('page-status');
    return !!(el && el.classList.contains('active-view'));
  }

  function startStatusPolling() {
    if (statusTimer) return;
    fetchStatus();
    statusTimer = setInterval(() => {
      if (isStatusVisible()) fetchStatus();
    }, STATUS_INTERVAL_MS);
  }

  function stopStatusPolling() {
    if (statusTimer) {
      clearInterval(statusTimer);
      statusTimer = null;
    }
  }

  // Navigation
  function switchPage(pageId, navItem) {
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    navItem.classList.add('active');
    const labels = {
      'inference': 'Inference',
      'thyroid': 'Thyroid Demo',
      'dicom3d': 'DICOM 3D',
      'about': 'About',
      'team': 'Team',
      'board': 'Board',
      'status': 'Status'
    };
    document.getElementById('header-title').innerText = labels[pageId];
    document.querySelectorAll('.page-view').forEach(el => el.classList.remove('active-view'));
    document.getElementById('page-' + pageId).classList.add('active-view');
    if (pageId === 'status') startStatusPolling();
    else stopStatusPolling();
  }
  window.switchPage = switchPage;

  // Sidebar toggle
  window.toggleSidebar = function() {
    const sidebar = document.getElementById('sidebar');
    sidebar.classList.toggle('collapsed');
  };

  // Model tabs
  function switchModel(modelId, tabItem) {
    currentModel = modelId;
    document.querySelectorAll('.model-tab').forEach(el => el.classList.remove('active-tab'));
    tabItem.classList.add('active-tab');
    const descEl = document.getElementById('model-desc');
    if (modelId === 'l4l5') {
      descEl.innerText = 'Lumbar L4/L5 locator demo with AI assistant.';
      isChatEnabled = true;
      if (chatMask) chatMask.style.display = detectionData ? 'none' : 'flex';
      setChatVisibility(true);
    } else if (modelId === 'cervical') {
      descEl.innerText = 'Cervical (tansit) detection demo. Default path: weights/cervical';
      isChatEnabled = false;
      if (chatMask) chatMask.style.display = 'flex';
      setChatVisibility(false);
    } else if (modelId === 'clavicle') {
      descEl.innerText = 'Clavicle model inference demo. Default path: weights/锁骨';
      isChatEnabled = false;
      if (chatMask) chatMask.style.display = 'flex';
      setChatVisibility(false);
    } else if (modelId === 't1') {
      descEl.innerText = 'T1 model inference demo. Default path: weights/T1';
      isChatEnabled = false;
      if (chatMask) chatMask.style.display = 'flex';
      setChatVisibility(false);
    } else if (modelId === 'pelvis') {
      descEl.innerText = 'Pelvis model inference demo (returns pelvic tilt angle). Default path: weights/骨盆';
      isChatEnabled = false;
      if (chatMask) chatMask.style.display = 'flex';
      setChatVisibility(false);
    } else {
      descEl.innerText = 'OPLL segmentation demo.';
      isChatEnabled = false;
      if (chatMask) chatMask.style.display = 'flex';
      setChatVisibility(false);
    }
  }
  window.switchModel = switchModel;

  const dashboardGrid = document.querySelector('.dashboard-grid');

  // Show/hide chat panel with smooth fade and expand other columns
  function setChatVisibility(visible) {
    if (!chatPanel || !dashboardGrid) return;
    if (visible) {
      // restore grid columns (right column original 320px)
      dashboardGrid.style.gridTemplateColumns = '280px 1fr 320px';
      chatPanel.classList.remove('hidden');
      // ensure mask visibility set appropriately
      if (chatMask) chatMask.style.display = detectionData ? 'none' : 'flex';
    } else {
      // collapse right column to 0 so other two expand
      dashboardGrid.style.gridTemplateColumns = '280px 1fr 0px';
      // fade chat out
      chatPanel.classList.add('hidden');
    }
  }

  // initialize chat visibility based on default model
  setChatVisibility(currentModel !== 'opll');

  // Thyroid demo wiring
  if (thyroidUploadBtn && thyroidFileInput) {
    thyroidUploadBtn.addEventListener('click', () => thyroidFileInput.click());
    thyroidUploadBtn.addEventListener('dragover', e => { e.preventDefault(); });
    thyroidUploadBtn.addEventListener('drop', e => {
      e.preventDefault();
      if (e.dataTransfer?.files?.length) {
        thyroidFileInput.files = e.dataTransfer.files;
        thyroidFileInput.dispatchEvent(new Event('change'));
      }
    });
  }

  if (thyroidFileInput) {
    thyroidFileInput.addEventListener('change', () => {
      const file = thyroidFileInput.files && thyroidFileInput.files[0];
      if (!file) return;
      thyroidStatusMsg(`已选择图片: ${file.name}`);
      const url = URL.createObjectURL(file);
      if (thyroidPreview) {
        thyroidPreview.src = url;
        thyroidPreview.style.display = 'block';
      }
      thyroidExampleB64 = null; // reset example when user picks a file
    });
  }

  if (thyroidExampleBtn) {
    thyroidExampleBtn.addEventListener('click', async () => {
      try {
        thyroidStatusMsg('正在加载示例图片...');
        const resp = await fetch('/static/img/Thyroid_test1.jpg');
        const blob = await resp.blob();
        const reader = new FileReader();
        reader.onloadend = () => {
          const res = reader.result || '';
          thyroidExampleB64 = res.toString().split(',').pop();
          thyroidPreview.src = res;
          thyroidPreview.style.display = 'block';
          if (thyroidFileInput) thyroidFileInput.value = '';
          thyroidStatusMsg('示例图片已加载，可点击开始推理');
        };
        reader.readAsDataURL(blob);
      } catch (e) {
        thyroidStatusMsg('示例图片加载失败', true);
      }
    });
  }
  if (thyroidRunBtn) {
    thyroidRunBtn.addEventListener('click', runThyroidInference);
  }

  // Errors
  function closeError() { errorOverlay.style.display = 'none'; }
  window.closeError = closeError;
  function showError(msg) {
    errorMsg.innerText = msg;
    errorOverlay.style.display = 'flex';
    loading.style.display = 'none';
  }

  // Conf slider
  if (confInput) confInput.addEventListener('input', e => confDisplay.innerText = e.target.value);

  // Example modal
  window.openExampleModal  = () => {
    const grid = document.querySelector('.example-grid');
    const folder = currentModel === 'opll' ? 'opll/' : '';
    grid.innerHTML = `
      <div onclick="selectExample(1)" class="ex-item"><img src="/static/img/compressed/${folder}1.png" loading="lazy"><span>Img 1</span></div>
      <div onclick="selectExample(2)" class="ex-item"><img src="/static/img/compressed/${folder}2.png" loading="lazy"><span>Img 2</span></div>
      <div onclick="selectExample(3)" class="ex-item"><img src="/static/img/compressed/${folder}3.png" loading="lazy"><span>Img 3</span></div>
      <div onclick="selectExample(4)" class="ex-item"><img src="/static/img/compressed/${folder}4.png" loading="lazy"><span>Img 4</span></div>
      <div onclick="selectExample(5)" class="ex-item"><img src="/static/img/compressed/${folder}5.png" loading="lazy"><span>Img 5</span></div>
      <div onclick="selectExample(6)" class="ex-item"><img src="/static/img/compressed/${folder}6.png" loading="lazy"><span>Img 6</span></div>
    `;
    document.getElementById('example-modal').style.display = 'flex';
  };
  window.closeExampleModal = () => document.getElementById('example-modal').style.display = 'none';
  window.selectExample     = (id) => { window.closeExampleModal(); handleFile(null, id); };

  // Drag & drop
  dropZone.addEventListener('click', () => fileInput.click());
  dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.style.borderColor = '#3b82f6'; dropZone.style.backgroundColor = '#eff6ff'; });
  dropZone.addEventListener('dragleave', () => { dropZone.style.borderColor = '#e2e8f0'; dropZone.style.backgroundColor = '#fafafa'; });
  dropZone.addEventListener('drop', e => {
    e.preventDefault();
    dropZone.style.borderColor = '#e2e8f0';
    dropZone.style.backgroundColor = '#fafafa';
    if (e.dataTransfer.files.length) handleFile(e.dataTransfer.files[0]);
  });
  // Zoom events
  if (resultCanvas && resultImg) {
    // 绂佹娴忚鍣ㄥ師鐢熸嫋鎷藉浘鐗?    resultImg.addEventListener('dragstart', e => e.preventDefault());

    resultCanvas.addEventListener('wheel', e => {
      e.preventDefault();
      const delta = e.deltaY < 0 ? 1.1 : 0.9;
      const prevScale = zScale;
      zScale = Math.min(6, Math.max(0.5, zScale * delta));
      // keep mouse position stable-ish
      const rect = resultCanvas.getBoundingClientRect();
      const cx = e.clientX - rect.left - rect.width / 2;
      const cy = e.clientY - rect.top - rect.height / 2;
      zTx += cx * (1/prevScale - 1/zScale);
      zTy += cy * (1/prevScale - 1/zScale);
      applyZoom();
    }, { passive: false });

    resultCanvas.addEventListener('mousedown', e => {
      zDragging = true;
      zLastX = e.clientX;
      zLastY = e.clientY;
      resultImg.style.cursor = 'grabbing';
    });
    window.addEventListener('mouseup', () => { zDragging = false; resultImg.style.cursor = 'grab'; });
    window.addEventListener('mouseleave', () => { zDragging = false; resultImg.style.cursor = 'grab'; });
    resultCanvas.addEventListener('mousemove', e => {
      if (!zDragging) return;
      const dx = e.clientX - zLastX;
      const dy = e.clientY - zLastY;
      zTx += dx;
      zTy += dy;
      zLastX = e.clientX;
      zLastY = e.clientY;
      applyZoom();
    });
    resultCanvas.addEventListener('dblclick', () => resetZoom());
  }
  fileInput.addEventListener('change', e => {
    if (e.target.files.length) {
      handleFile(e.target.files[0]);
      fileInput.value = '';
    }
  });

  // Core upload handler
  function handleFile(file, exampleId=null) {
    if (file && !file.type.startsWith('image/')) { showError('Please upload image files (PNG/JPG)'); return; }
    errorOverlay.style.display = 'none';
    resultImg.style.display = 'none';
    emptyState.style.display = 'none';
    loading.style.display = 'flex';

    const endpointMap = {
      l4l5: '/api/l4l5locator',
      opll: '/api/opll',
      cervical: '/api/extra_model_infer',
      clavicle: '/api/extra_model_infer',
      t1: '/api/extra_model_infer',
      pelvis: '/api/extra_model_infer',
      sacrum: '/api/extra_model_infer',
    };
    const apiEndpoint = endpointMap[currentModel];
    if (!apiEndpoint) {
      showError(`Unsupported model: ${currentModel}`);
      loading.style.display = 'none';
      return;
    }

    const formData = new FormData();
    if (confInput) formData.append('conf', confInput.value);
    formData.append('model_name', currentModel);
    if (exampleId) formData.append('use_example', exampleId);
    else if (file) formData.append('file', file);
    else { showError('No image selected'); loading.style.display = 'none'; return; }

    fetch(apiEndpoint, { method: 'POST', body: formData })
      .then(response => {
        if (!response.ok) {
          return response.json().then(errData => { throw new Error(errData.message || response.statusText); })
            .catch(() => { throw new Error(response.statusText + ' (Check Server Logs)'); });
        }
        return response.json();
      })
      .then(data => {
        if (data.status === 'ok') {
          if (currentModel === 'l4l5') {
            if (chatMask) chatMask.style.display = 'none';
            detectionData = {
              score: data.score,
              cobb_deg: data.cobb_deg,
              curvature_deg: data.curvature_deg,
              curvature_per_seg: data.curvature_per_seg,
              vertebrae: data.vertebrae,
              spine_midpoints: data.spine_midpoints,
              cobb_l2_line: data.cobb_l2_line,
              cobb_s1_line: data.cobb_s1_line,
              peak_y: data.peak_y
            };
            conversationHistory = [];
          }

          if (currentModel === 'pelvis' && data.pelvic_tilt_deg !== undefined) {
            appendChat('System', `Pelvic tilt angle: ${Number(data.pelvic_tilt_deg).toFixed(2)} deg`);
          }

          resultImg.onload = () => {
            if (resultCanvas) {
              resultImg.style.height = resultCanvas.clientHeight + 'px';
              resultImg.style.width = 'auto';
              resultImg.style.maxHeight = resultCanvas.clientHeight + 'px';
            }
            resetZoom();
            loading.style.display = 'none';
            resultImg.style.display = 'block';
            if (currentModel === 'l4l5') autoSendAIDiagnosis();
          };
          resultImg.onerror = () => showError('Failed to decode returned image');
          resultImg.src = 'data:' + (data.image_mimetype || 'image/png') + ';base64,' + data.image_base64;
        } else {
          showError('Inference failed: ' + (data.message || 'unknown error'));
        }
      })
      .catch(error => { console.error(error); showError('Request failed: ' + (error.message || 'Network Error')); });
  }

  // Chat functions
  function appendChat(sender, msg) {
    if (!chatLog) return;
    const div = document.createElement('div');
    div.className = 'chat-msg ' + (sender === 'You' ? 'you' : 'ai');
    const bubble = document.createElement('div');
    bubble.className = 'bubble';
    if (sender === 'AI') {
      bubble.innerHTML = marked.parse(msg);
    } else {
      bubble.textContent = `${sender}: ${msg}`;
    }
    div.appendChild(bubble);
    chatLog.appendChild(div);
    chatLog.scrollTop = chatLog.scrollHeight;
    return bubble;
  }

  function autoSendAIDiagnosis() {
    if (!detectionData) return;
    const systemMsg = `AI auto analysis.\nScore: ${detectionData.score >= 0 ? '+' : ''}${detectionData.score}, Cobb: ${detectionData.cobb_deg.toFixed(1)} deg, Curvature: ${detectionData.curvature_deg.toFixed(2)} deg`;
    appendChat('System', systemMsg);
    sendAIMessage(null, true);
  }
  function sendAIMessage(userMsg = null, isInitial = false) {
    if (!isChatEnabled) {
      appendChat('System', 'AI chat is only enabled for the lumbar model.');
      return;
    }
    if (!detectionData) {
      appendChat('System', 'Please run inference first.');
      return;
    }

    if (userMsg) {
      appendChat('You', userMsg);
      conversationHistory.push({ role: 'user', content: userMsg });
    }

    chatSend.disabled = true;
    const aiBubble = appendChat('AI', 'Thinking...');

    const requestBody = isInitial ? detectionData : {
      ...detectionData,
      conversation: conversationHistory
    };

    fetch('/api/spine_analysis', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(requestBody)
    })
    .then(response => {
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let aiResponse = '';
      aiBubble.innerHTML = '';

      function readStream() {
        reader.read().then(({ done, value }) => {
          if (done) {
            chatSend.disabled = false;
            if (aiResponse) conversationHistory.push({ role: 'assistant', content: aiResponse });
            return;
          }

          const chunk = decoder.decode(value, { stream: true });
          const lines = chunk.split('\n');

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const data = line.slice(6);
              if (data === '[DONE]') {
                chatSend.disabled = false;
                if (aiResponse) conversationHistory.push({ role: 'assistant', content: aiResponse });
                return;
              }
              try {
                const json = JSON.parse(data);
                if (json.content) {
                  aiResponse += json.content;
                  aiBubble.innerHTML = marked.parse(aiResponse);
                  chatLog.scrollTop = chatLog.scrollHeight;
                } else if (json.error) {
                  aiBubble.innerHTML = 'Error: ' + json.error;
                  chatSend.disabled = false;
                  return;
                }
              } catch (e) {}
            }
          }
          readStream();
        });
      }
      readStream();
    })
    .catch(error => {
      aiBubble.innerHTML = 'Request failed: ' + error.message;
      chatSend.disabled = false;
    });
  }

  if (chatSend) {
    chatSend.addEventListener('click', () => {
      const msg = chatText ? chatText.value.trim() : '';
      if (!msg) return;
      sendAIMessage(msg);
      chatText.value = '';
    });
  }
  
  if (chatText) {
    chatText.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        const msg = chatText.value.trim();
        if (msg) {
          sendAIMessage(msg);
          chatText.value = '';
        }
      }
    });
  }

  // --- Model diagram rendering ---
  function makeSVG(tag, attrs) {
    const ns = 'http://www.w3.org/2000/svg';
    const el = document.createElementNS(ns, tag);
    for (const k in attrs) el.setAttribute(k, attrs[k]);
    return el;
  }

  function setupDiagram(container) {
    container.innerHTML = '';
    const tip = document.createElement('div');
    tip.className = 'diagram-tooltip';
    container.appendChild(tip);
    return tip;
  }

  function bindTooltip(target, text, container, tip) {
    const place = (e) => {
      const rect = container.getBoundingClientRect();
      tip.style.left = (e.clientX - rect.left) + 'px';
      tip.style.top = (e.clientY - rect.top - 10) + 'px';
    };
    target.addEventListener('mouseenter', (e) => {
      tip.style.display = 'block';
      tip.textContent = text;
      place(e);
    });
    target.addEventListener('mousemove', place);
    target.addEventListener('mouseleave', () => { tip.style.display = 'none'; });
  }

  function addArrowDefs(svg, id, color) {
    const defs = makeSVG('defs', {});
    const marker = makeSVG('marker', {
      id,
      viewBox: '0 0 10 10',
      refX: '7',
      refY: '5',
      markerWidth: '6',
      markerHeight: '6',
      orient: 'auto'
    });
    marker.appendChild(makeSVG('path', { d: 'M 0 0 L 10 5 L 0 10 z', fill: color }));
    defs.appendChild(marker);
    svg.appendChild(defs);
    return `url(#${id})`;
  }

  function addText(svg, attrs, text) {
    const el = makeSVG('text', attrs);
    el.textContent = text;
    svg.appendChild(el);
    return el;
  }

  function drawHRNetDiagram() {
    const container = document.getElementById('hrnet-diagram');
    if (!container) return;
    const tip = setupDiagram(container);
    const svg = makeSVG('svg', { viewBox: '0 0 920 200', preserveAspectRatio: 'xMidYMid meet' });
    const arrow = addArrowDefs(svg, 'arrow-hrnet', 'rgba(3,102,214,0.85)');

    const blockW = 74;
    const blockH = 22;
    const rowGap = 32;
    const topY = 30;
    const rows = [0, 1, 2, 3].map(i => topY + i * rowGap);
    const stageX = [240, 360, 480, 600];
    const stageLabels = ['Stage1', 'Stage2', 'Stage3', 'Stage4'];
    const resLabels = ['1x', '1/2x', '1/4x', '1/8x'];

    const input = makeSVG('rect', { x: 20, y: rows[0], width: 70, height: blockH, rx: 6, class: 'diagram-node' });
    svg.appendChild(input);
    addText(svg, { x: 26, y: rows[0] + 15, class: 'diagram-text' }, 'Input');
    addText(svg, { x: 26, y: rows[0] + 27, class: 'diagram-muted' }, '1xH x W');
    bindTooltip(input, 'Input X-Ray (1-channel)', container, tip);

    const stem = makeSVG('rect', { x: 110, y: rows[0], width: 90, height: blockH, rx: 6, class: 'diagram-node' });
    svg.appendChild(stem);
    addText(svg, { x: 118, y: rows[0] + 15, class: 'diagram-text' }, 'Stem');
    addText(svg, { x: 118, y: rows[0] + 27, class: 'diagram-muted' }, 'Conv + BN');
    bindTooltip(stem, 'Stem: 3x3 convs + BN + ReLU', container, tip);
    svg.appendChild(makeSVG('line', { x1: 90, y1: rows[0] + blockH / 2, x2: 110, y2: rows[0] + blockH / 2, stroke: '#60a5fa', 'stroke-width': 2, 'marker-end': arrow }));

    const stageBlocks = [];
    stageLabels.forEach((label, sIdx) => {
      const rowsCount = sIdx + 1;
      const groupX = stageX[sIdx] - 8;
      const groupY = rows[0] - 16;
      const groupH = (rowsCount - 1) * rowGap + blockH + 20;
      svg.appendChild(makeSVG('rect', {
        x: groupX,
        y: groupY,
        width: blockW + 16,
        height: groupH,
        rx: 8,
        fill: 'none',
        stroke: '#cbd5f5',
        'stroke-width': 1,
        'stroke-dasharray': '4 3'
      }));
      addText(svg, { x: groupX + 4, y: groupY - 4, class: 'diagram-muted' }, label);

      stageBlocks[sIdx] = [];
      for (let r = 0; r < rowsCount; r++) {
        const x = stageX[sIdx];
        const y = rows[r];
        const rect = makeSVG('rect', { x, y, width: blockW, height: blockH, rx: 6, class: 'diagram-node' });
        svg.appendChild(rect);
        addText(svg, { x: x + 8, y: y + 15, class: 'diagram-text' }, resLabels[r]);
        bindTooltip(rect, `${label} - ${resLabels[r]} stream\nResidual blocks + exchange`, container, tip);
        stageBlocks[sIdx].push({ x, y });
      }

      const fx = stageX[sIdx] + blockW / 2;
      svg.appendChild(makeSVG('line', {
        x1: fx, y1: rows[0] + blockH / 2,
        x2: fx, y2: rows[rowsCount - 1] + blockH / 2,
        stroke: '#93c5fd',
        'stroke-width': 1.2
      }));
    });

    svg.appendChild(makeSVG('line', {
      x1: 200, y1: rows[0] + blockH / 2,
      x2: stageX[0], y2: rows[0] + blockH / 2,
      stroke: '#60a5fa',
      'stroke-width': 2,
      'marker-end': arrow
    }));

    for (let s = 0; s < stageBlocks.length - 1; s++) {
      for (let r = 0; r < stageBlocks[s].length; r++) {
        const a = stageBlocks[s][r];
        const b = stageBlocks[s + 1][r];
        svg.appendChild(makeSVG('line', {
          x1: a.x + blockW, y1: a.y + blockH / 2,
          x2: b.x, y2: b.y + blockH / 2,
          stroke: '#60a5fa',
          'stroke-width': 1.6,
          'marker-end': arrow
        }));
      }
      if (stageBlocks[s + 1].length > stageBlocks[s].length) {
        const from = stageBlocks[s][stageBlocks[s].length - 1];
        const to = stageBlocks[s + 1][stageBlocks[s + 1].length - 1];
        svg.appendChild(makeSVG('line', {
          x1: from.x + blockW, y1: from.y + blockH / 2,
          x2: to.x, y2: to.y + blockH / 2,
          stroke: '#94a3b8',
          'stroke-width': 1.2,
          'stroke-dasharray': '4 3'
        }));
      }
    }

    const head = makeSVG('rect', { x: 720, y: 56, width: 150, height: 60, rx: 8, class: 'diagram-node' });
    svg.appendChild(head);
    addText(svg, { x: 732, y: 78, class: 'diagram-text' }, 'Fusion Head');
    addText(svg, { x: 732, y: 94, class: 'diagram-muted' }, '1x1 Conv + Heatmap');
    bindTooltip(head, 'Multi-res fusion -> 1x1 conv -> keypoint heatmaps', container, tip);

    stageBlocks[3].forEach((b, idx) => {
      const targetY = 64 + idx * 14;
      svg.appendChild(makeSVG('line', {
        x1: b.x + blockW, y1: b.y + blockH / 2,
        x2: 720, y2: targetY,
        stroke: '#60a5fa',
        'stroke-width': 1.2,
        'stroke-dasharray': '3 3'
      }));
    });

    const out = makeSVG('rect', { x: 880, y: 70, width: 30, height: 22, rx: 5, class: 'diagram-node' });
    svg.appendChild(out);
    addText(svg, { x: 882, y: 84, class: 'diagram-muted' }, 'KP');
    svg.appendChild(makeSVG('line', {
      x1: 870, y1: 86,
      x2: 880, y2: 81,
      stroke: '#60a5fa',
      'stroke-width': 2,
      'marker-end': arrow
    }));

    container.appendChild(svg);
  }

  function drawVGG16BNNDiagram() {
    const container = document.getElementById('hed-diagram');
    if (!container) return;
    const tip = setupDiagram(container);
    const svg = makeSVG('svg', { viewBox: '0 0 920 200', preserveAspectRatio: 'xMidYMid meet' });
    const arrow = addArrowDefs(svg, 'arrow-vgg', 'rgba(3,102,214,0.85)');

    addText(svg, { x: 20, y: 16, class: 'diagram-muted' }, 'VGG16-BNN: BinaryConv + BN + ReLU');

    const input = makeSVG('rect', { x: 20, y: 32, width: 70, height: 26, rx: 6, class: 'diagram-node' });
    svg.appendChild(input);
    addText(svg, { x: 26, y: 49, class: 'diagram-text' }, 'Input');
    bindTooltip(input, 'Input image (1-channel)', container, tip);

    const blocks = [
      { name: 'Block1', ch: 64, reps: 2 },
      { name: 'Block2', ch: 128, reps: 2 },
      { name: 'Block3', ch: 256, reps: 3 },
      { name: 'Block4', ch: 512, reps: 3 },
      { name: 'Block5', ch: 512, reps: 3 }
    ];
    const blockW = 100;
    const blockH = 36;
    const startX = 120;
    const gap = 120;
    const topY = 26;
    const sideY = 82;

    blocks.forEach((b, i) => {
      const x = startX + i * gap;
      const rect = makeSVG('rect', { x, y: topY, width: blockW, height: blockH, rx: 6, class: 'diagram-node' });
      svg.appendChild(rect);
      addText(svg, { x: x + 8, y: topY + 16, class: 'diagram-text' }, b.name);
      addText(svg, { x: x + 8, y: topY + 30, class: 'diagram-muted' }, `${b.ch}ch | W1/A1`);
      bindTooltip(rect, `${b.name}\nBinaryConv 3x3 x${b.reps}\nBN + ReLU`, container, tip);

      const side = makeSVG('rect', { x: x + blockW / 2 - 14, y: sideY, width: 28, height: 14, rx: 4, class: 'diagram-node' });
      svg.appendChild(side);
      addText(svg, { x: x + blockW / 2, y: sideY + 11, 'text-anchor': 'middle', class: 'diagram-muted' }, 'Side');

      svg.appendChild(makeSVG('line', {
        x1: x + blockW / 2, y1: topY + blockH,
        x2: x + blockW / 2, y2: sideY,
        stroke: '#60a5fa',
        'stroke-width': 1.2
      }));

      if (i === 0) {
        svg.appendChild(makeSVG('line', {
          x1: 90, y1: topY + blockH / 2,
          x2: x, y2: topY + blockH / 2,
          stroke: '#60a5fa',
          'stroke-width': 2,
          'marker-end': arrow
        }));
      } else {
        const prevX = startX + (i - 1) * gap + blockW;
        svg.appendChild(makeSVG('line', {
          x1: prevX, y1: topY + blockH / 2,
          x2: x, y2: topY + blockH / 2,
          stroke: '#60a5fa',
          'stroke-width': 2,
          'marker-end': arrow
        }));
      }
    });

    const fuse = makeSVG('rect', { x: 720, y: 24, width: 120, height: 48, rx: 6, class: 'diagram-node' });
    svg.appendChild(fuse);
    addText(svg, { x: 732, y: 44, class: 'diagram-text' }, 'Fuse');
    addText(svg, { x: 732, y: 60, class: 'diagram-muted' }, '1x1 Conv');
    bindTooltip(fuse, 'Side outputs fused by 1x1 conv', container, tip);

    blocks.forEach((b, i) => {
      const sx = startX + i * gap + blockW / 2;
      svg.appendChild(makeSVG('line', {
        x1: sx, y1: sideY + 14,
        x2: 720, y2: 48,
        stroke: '#94a3b8',
        'stroke-width': 1.1,
        'stroke-dasharray': '4 3'
      }));
    });

    const out = makeSVG('rect', { x: 860, y: 32, width: 46, height: 26, rx: 6, class: 'diagram-node' });
    svg.appendChild(out);
    addText(svg, { x: 868, y: 49, class: 'diagram-text' }, 'Edge');
    svg.appendChild(makeSVG('line', {
      x1: 840, y1: 48,
      x2: 860, y2: 45,
      stroke: '#60a5fa',
      'stroke-width': 2,
      'marker-end': arrow
    }));

    container.appendChild(svg);
  }

  function drawUNetDiagram() {
    const container = document.getElementById('unet-diagram');
    if (!container) return;
    const tip = setupDiagram(container);
    const svg = makeSVG('svg', { viewBox: '0 0 920 240', preserveAspectRatio: 'xMidYMid meet' });
    const arrow = addArrowDefs(svg, 'arrow-unet', 'rgba(3,102,214,0.85)');

    const enc = [
      { name: 'Down1', in: 1, out: 64 },
      { name: 'Down2', in: 64, out: 128 },
      { name: 'Down3', in: 128, out: 256 },
      { name: 'Down4', in: 256, out: 512 }
    ];
    const dec = [
      { name: 'Up4', in: 1024, out: 512 },
      { name: 'Up3', in: 512, out: 256 },
      { name: 'Up2', in: 256, out: 128 },
      { name: 'Up1', in: 128, out: 64 }
    ];
    const bott = { name: 'Bottleneck', in: 512, out: 1024 };

    const leftX = 70;
    const rightX = 640;
    const boxW = 86;
    const boxH = 26;
    const vGap = 26;
    const topY = 18;
    const encY = [0, 1, 2, 3].map(i => topY + i * (boxH + vGap));
    const decY = [...encY].reverse();

    const input = makeSVG('rect', { x: 20, y: encY[0], width: 40, height: boxH, rx: 6, class: 'diagram-node' });
    svg.appendChild(input);
    addText(svg, { x: 26, y: encY[0] + 17, class: 'diagram-text' }, 'In');
    svg.appendChild(makeSVG('line', {
      x1: 60, y1: encY[0] + boxH / 2,
      x2: leftX, y2: encY[0] + boxH / 2,
      stroke: '#60a5fa',
      'stroke-width': 2,
      'marker-end': arrow
    }));

    enc.forEach((b, i) => {
      const y = encY[i];
      const rect = makeSVG('rect', { x: leftX, y, width: boxW, height: boxH, rx: 6, class: 'diagram-node' });
      svg.appendChild(rect);
      addText(svg, { x: leftX + 6, y: y + 16, class: 'diagram-text' }, b.name);
      addText(svg, { x: leftX + 6, y: y + 27, class: 'diagram-muted' }, `${b.in}->${b.out}`);
      bindTooltip(rect, `${b.name}\nDoubleConv 3x3 x2`, container, tip);
      if (i < enc.length - 1) {
        svg.appendChild(makeSVG('line', {
          x1: leftX + boxW / 2, y1: y + boxH,
          x2: leftX + boxW / 2, y2: y + boxH + vGap - 4,
          stroke: '#60a5fa',
          'stroke-width': 2,
          'marker-end': arrow
        }));
      }
    });

    const bx = 360;
    const by = encY[encY.length - 1] + boxH + 10;
    const bottleneck = makeSVG('rect', { x: bx, y: by, width: boxW, height: boxH, rx: 6, class: 'diagram-node' });
    svg.appendChild(bottleneck);
    addText(svg, { x: bx + 6, y: by + 16, class: 'diagram-text' }, bott.name);
    addText(svg, { x: bx + 6, y: by + 27, class: 'diagram-muted' }, `${bott.in}->${bott.out}`);
    bindTooltip(bottleneck, 'Bottom: DoubleConv 3x3 x2', container, tip);

    svg.appendChild(makeSVG('line', {
      x1: leftX + boxW / 2, y1: encY[encY.length - 1] + boxH,
      x2: bx + boxW / 2, y2: by,
      stroke: '#60a5fa',
      'stroke-width': 2,
      'marker-end': arrow
    }));

    dec.forEach((b, i) => {
      const y = decY[i];
      const rect = makeSVG('rect', { x: rightX, y, width: boxW, height: boxH, rx: 6, class: 'diagram-node' });
      svg.appendChild(rect);
      addText(svg, { x: rightX + 6, y: y + 16, class: 'diagram-text' }, b.name);
      addText(svg, { x: rightX + 6, y: y + 27, class: 'diagram-muted' }, `${b.in}->${b.out}`);
      bindTooltip(rect, `${b.name}\nUpConv + DoubleConv`, container, tip);
      if (i < dec.length - 1) {
        svg.appendChild(makeSVG('line', {
          x1: rightX + boxW / 2, y1: y,
          x2: rightX + boxW / 2, y2: y - vGap + 4,
          stroke: '#60a5fa',
          'stroke-width': 2,
          'marker-end': arrow
        }));
      }
    });

    svg.appendChild(makeSVG('line', {
      x1: bx + boxW / 2, y1: by + boxH,
      x2: rightX + boxW / 2, y2: decY[0] + boxH,
      stroke: '#60a5fa',
      'stroke-width': 2,
      'marker-end': arrow
    }));

    for (let i = 0; i < enc.length; i++) {
      const sx = leftX + boxW;
      const sy = encY[i] + boxH / 2;
      const tx = rightX;
      const ty = decY[i] + boxH / 2;
      const mx = (sx + tx) / 2;
      svg.appendChild(makeSVG('path', {
        d: `M ${sx} ${sy} C ${mx} ${sy} ${mx} ${ty} ${tx} ${ty}`,
        stroke: '#94a3b8',
        'stroke-width': 1.2,
        'stroke-dasharray': '4 3',
        fill: 'none'
      }));
    }

    const out = makeSVG('rect', { x: 780, y: encY[0], width: 80, height: boxH, rx: 6, class: 'diagram-node' });
    svg.appendChild(out);
    addText(svg, { x: 786, y: encY[0] + 17, class: 'diagram-text' }, 'Output');
    addText(svg, { x: 786, y: encY[0] + 27, class: 'diagram-muted' }, '1x1 Conv');
    svg.appendChild(makeSVG('line', {
      x1: rightX + boxW, y1: encY[0] + boxH / 2,
      x2: 780, y2: encY[0] + boxH / 2,
      stroke: '#60a5fa',
      'stroke-width': 2,
      'marker-end': arrow
    }));

    container.appendChild(svg);
  }

  // remote status polling (only when status tab visible)
  if (isStatusVisible()) startStatusPolling();

  // draw on load
  drawHRNetDiagram(); drawVGG16BNNDiagram(); drawUNetDiagram();
});

