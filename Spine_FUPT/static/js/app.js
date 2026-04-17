(() => {
  "use strict";

  const state = {
    user: null,
    activeView: "overview",
    overviewClockTimer: null,
    statusPollTimer: null,
    realtime: {
      ws: null,
      ready: false,
      shouldReconnect: false,
      reconnectTimer: null,
      refreshTimer: null,
      chatRefreshTimer: null,
    },
    logs: {
      loaded: false,
      loading: false,
      items: [],
    },
    users: {
      loaded: false,
      loading: false,
      list: [],
      selectedId: null,
    },
    questionnaires: {
      loaded: false,
      loading: false,
      saving: false,
      items: [],
      chatsLoaded: false,
      chatsLoading: false,
      chats: [],
      chatSelectedId: null,
      chatMobileDetailOpen: false,
      chatMessagesMap: {},
      chatMessagesLoading: false,
      realtimeChatChannel: "",
      chatReadTimers: {},
      directoryMode: false,
      directoryLoading: false,
      directoryLoaded: false,
      directoryItems: [],
      directoryKeyword: "",
      detailLoading: false,
      detailId: null,
      detail: null,
      detailSettingsOpen: false,
      assignModalOpen: false,
      assignLoading: false,
      assignSubmitting: false,
      assignCandidates: [],
      assignSearch: "",
      assignSelectedIds: [],
      createMode: false,
      settingQuestionId: null,
      draft: {
        title: "",
        introHtml: "",
        questions: [],
        nextId: 1,
      },
    },
    reviews: {
      loaded: false,
      loading: false,
      submitting: false,
      deletingId: null,
      reclassifyId: null,
      list: [],
      selectedId: null,
      detailMap: {},
      noteDraftMap: {},
      mobileDetailOpen: false,
      viewer: {
        imageSource: "ai",
        hasAi: false,
        hasRaw: false,
        scale: 1,
        tx: 0,
        ty: 0,
        minScale: 0.3,
        maxScale: 6,
        dragging: false,
        startX: 0,
        startY: 0,
        startTx: 0,
        startTy: 0,
      },
    },
    patients: {
      loaded: false,
      loading: false,
      list: [],
      search: "",
      sortKey: "updated_at",
      sortDir: "desc",
      detailId: null,
      detailTab: "basic",
      detailEditing: false,
      detailMap: {},
      listScrollTop: 0,
      register: {
        active: false,
        token: "",
        channel: "",
        formState: {},
        focusField: "",
        status: "",
        ws: null,
        wsReady: false,
        wsShouldReconnect: false,
        applyingRemote: false,
        fieldTimers: {},
      },
    },
  };

  const VIEW_META = {
    overview: {
      title: "总览",
      desc: "总览模块占位，后续接入统计与任务卡片。",
    },
    patients: {
      title: "患者列表",
      desc: "患者列表模块占位，后续接入筛选、详情与随访记录。",
    },
    reviews: {
      title: "复核列表",
      desc: "复核列表模块占位，后续接入影像审核与协作评论。",
    },
    questionnaires: {
      title: "问卷调查",
      desc: "问卷调查模块占位，后续接入问卷发布与回收统计。",
    },
    chat: {
      title: "聊天",
      desc: "聊天模块占位，后续接入实时会话与消息通知。",
    },
    logs: {
      title: "日志",
      desc: "日志模块占位，后续接入系统行为追踪与检索。",
    },
    "server-status": {
      title: "推理服务器状态",
      desc: "推理服务器状态模块占位，后续接入服务健康监控。",
    },
    users: {
      title: "用户列表",
      desc: "用户列表模块占位，后续接入账号与权限管理。",
    },
  };
  const VIEW_STATE_KEY = "spine_fupt_active_view";
  const REVIEW_VIEWER_CACHE_KEY = "spine_fupt_review_viewer_transform_v1";
  const OVERVIEW_CACHE_KEY = "spine_fupt_overview_cache_v1";

  const el = (id) => document.getElementById(id);

  function getWsUrl() {
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    return `${proto}//${window.location.host}/ws`;
  }

  function normalizeViewKey(viewKey) {
    return Object.prototype.hasOwnProperty.call(VIEW_META, viewKey) ? viewKey : "overview";
  }

  function saveActiveView(viewKey) {
    const key = normalizeViewKey(viewKey);
    try {
      window.localStorage.setItem(VIEW_STATE_KEY, key);
    } catch (_err) {
      // Ignore storage errors.
    }
    const nextHash = `view=${encodeURIComponent(key)}`;
    if (window.location.hash !== `#${nextHash}`) {
      window.history.replaceState(null, "", `#${nextHash}`);
    }
  }

  function readActiveView() {
    const hash = String(window.location.hash || "");
    const m = hash.match(/view=([a-zA-Z0-9_-]+)/);
    if (m && m[1]) {
      return normalizeViewKey(m[1]);
    }
    try {
      return normalizeViewKey(window.localStorage.getItem(VIEW_STATE_KEY) || "overview");
    } catch (_err) {
      return "overview";
    }
  }

  function isMobile() {
    return window.matchMedia("(max-width: 768px)").matches;
  }

  async function api(path, options = {}) {
    const method = options.method || "GET";
    const headers = Object.assign({}, options.headers || {});
    const fetchOptions = {
      method,
      headers,
      credentials: "same-origin",
    };

    if (options.body !== undefined) {
      headers["Content-Type"] = "application/json";
      fetchOptions.body = JSON.stringify(options.body);
    }

    const response = await fetch(path, fetchOptions);
    let payload = {};
    try {
      payload = await response.json();
    } catch (_err) {
      payload = {};
    }

    if (!response.ok || payload.ok === false) {
      const err = new Error(
        (payload && payload.error && payload.error.message) ||
          (payload && payload.message) ||
          `Request failed (${response.status})`
      );
      err.status = response.status;
      throw err;
    }

    return payload.data || {};
  }

  async function apiMultipart(path, formData, options = {}) {
    const method = options.method || "POST";
    const fetchOptions = {
      method,
      body: formData,
      credentials: "same-origin",
      headers: Object.assign({}, options.headers || {}),
    };

    const response = await fetch(path, fetchOptions);
    let payload = {};
    try {
      payload = await response.json();
    } catch (_err) {
      payload = {};
    }

    if (!response.ok || payload.ok === false) {
      const err = new Error(
        (payload && payload.error && payload.error.message) ||
          (payload && payload.message) ||
          `Request failed (${response.status})`
      );
      err.status = response.status;
      throw err;
    }

    return payload.data || {};
  }

  function showToast(message, type = "info", options = {}) {
    const host = el("toast-root");
    if (!host) {
      return;
    }
    const position = "bottom-right";
    host.classList.remove("top-center", "bottom-right");
    host.classList.add(position);
    const node = document.createElement("div");
    node.className = `toast ${type}`;
    node.textContent = String(message || "Done");
    host.appendChild(node);
    window.setTimeout(() => node.remove(), 2600);
  }

  function setAuthVisibility(authenticated) {
    const loginScreen = el("login-screen");
    const appScreen = el("app-screen");

    if (loginScreen) {
      loginScreen.classList.toggle("hidden", authenticated);
    }
    if (appScreen) {
      appScreen.classList.toggle("hidden", !authenticated);
    }
    if (!authenticated) {
      stopOverviewClock();
      stopStatusPolling();
      teardownRealtimeSystemWs();
    }
  }

  function setLoginLoading(loading) {
    const loginBtn = el("login-btn");
    const btnText = el("login-btn-text");
    const spinner = el("login-loading");

    if (loginBtn) {
      loginBtn.disabled = loading;
    }
    if (btnText) {
      btnText.style.display = loading ? "none" : "inline";
    }
    if (spinner) {
      spinner.style.display = loading ? "inline-block" : "none";
    }
  }

  function clearLoginError() {
    const box = el("login-error");
    if (!box) {
      return;
    }
    box.textContent = "";
    box.classList.remove("show");
  }

  function showLoginError(message) {
    const box = el("login-error");
    if (!box) {
      showToast(message || "Login failed", "error");
      return;
    }
    box.textContent = message || "Login failed";
    box.classList.add("show");
  }

  function userDisplayName(user) {
    if (!user) {
      return "-";
    }
    return user.display_name || user.username || "-";
  }

  function formatOverviewDate(now) {
    const week = ["日", "一", "二", "三", "四", "五", "六"];
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, "0");
    const day = String(now.getDate()).padStart(2, "0");
    const hours = String(now.getHours()).padStart(2, "0");
    const minutes = String(now.getMinutes()).padStart(2, "0");
    const seconds = String(now.getSeconds()).padStart(2, "0");
    const weekday = week[now.getDay()];
    return {
      time: `${hours}:${minutes}:${seconds}`,
      date: `${year}-${month}-${day} 周${weekday}`,
    };
  }

  function renderOverviewDate() {
    const timeNode = el("overview-time");
    const dateNode = el("overview-date");
    if (!timeNode || !dateNode) {
      return;
    }
    const dt = formatOverviewDate(new Date());
    timeNode.textContent = dt.time;
    dateNode.textContent = dt.date;
  }

  function setOverviewMetrics(statsOrPatientTotal, maybePendingReviews) {
    const stats =
      statsOrPatientTotal && typeof statsOrPatientTotal === "object"
        ? statsOrPatientTotal
        : {
            patient_total: statsOrPatientTotal,
            pending_reviews: maybePendingReviews,
          };

    const followupActive = Number(stats.followup_active);
    const followupDueSoon = Number(stats.followup_due_soon);
    const pendingReviews = Number(stats.pending_reviews);
    const followupOverdue = Number(stats.followup_overdue);
    const todaySchedules = Number(stats.today_schedules);
    const legacyPatientTotal = Number(stats.patient_total);

    const taskTotal = Number.isFinite(pendingReviews)
      ? pendingReviews + (Number.isFinite(followupOverdue) ? followupOverdue : 0)
      : Number.isFinite(todaySchedules)
        ? todaySchedules
        : NaN;

    const followupNode = el("overview-followup-active");
    const dueSoonNode = el("overview-followup-due-soon");
    const taskNode = el("overview-task-total");

    if (followupNode) {
      followupNode.textContent = Number.isFinite(followupActive)
        ? String(followupActive)
        : Number.isFinite(legacyPatientTotal)
          ? String(legacyPatientTotal)
          : "-";
    }
    if (dueSoonNode) {
      dueSoonNode.textContent = Number.isFinite(followupDueSoon)
        ? String(followupDueSoon)
        : Number.isFinite(pendingReviews)
          ? String(pendingReviews)
          : "-";
    }
    if (taskNode) {
      taskNode.textContent = Number.isFinite(taskTotal) ? String(taskTotal) : "-";
    }

    const legacyPatientNode = el("overview-patient-count");
    const legacyPendingNode = el("overview-pending-count");
    if (legacyPatientNode) {
      legacyPatientNode.textContent = Number.isFinite(legacyPatientTotal) ? String(legacyPatientTotal) : "-";
    }
    if (legacyPendingNode) {
      legacyPendingNode.textContent = Number.isFinite(pendingReviews) ? String(pendingReviews) : "-";
    }
  }

  function withTimeout(promise, timeoutMs) {
    let timer = null;
    const timeoutPromise = new Promise((_, reject) => {
      timer = window.setTimeout(() => {
        reject(new Error("request_timeout"));
      }, timeoutMs);
    });
    return Promise.race([promise, timeoutPromise]).finally(() => {
      if (timer) {
        window.clearTimeout(timer);
      }
    });
  }

  function readOverviewCache() {
    try {
      const raw = window.localStorage.getItem(OVERVIEW_CACHE_KEY);
      if (!raw) {
        return null;
      }
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object") {
        return null;
      }
      return parsed;
    } catch (_err) {
      return null;
    }
  }

  function writeOverviewCache(payload) {
    try {
      window.localStorage.setItem(
        OVERVIEW_CACHE_KEY,
        JSON.stringify({
          ...payload,
          cached_at: Date.now(),
        })
      );
    } catch (_err) {
      // Ignore storage write failures.
    }
  }

  function formatShortDateTime(isoText) {
    const dt = parseApiDate(isoText);
    if (Number.isNaN(dt.getTime())) {
      return "--";
    }
    const mm = String(dt.getMonth() + 1).padStart(2, "0");
    const dd = String(dt.getDate()).padStart(2, "0");
    const hh = String(dt.getHours()).padStart(2, "0");
    const mi = String(dt.getMinutes()).padStart(2, "0");
    return `${mm}-${dd} ${hh}:${mi}`;
  }

  function formatDateOnly(isoText) {
    const dt = parseApiDate(isoText);
    if (Number.isNaN(dt.getTime())) {
      return "--";
    }
    const y = dt.getFullYear();
    const m = String(dt.getMonth() + 1).padStart(2, "0");
    const d = String(dt.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  function formatTimelineDateTime(isoText) {
    const dt = parseApiDate(isoText);
    if (Number.isNaN(dt.getTime())) {
      return "--";
    }
    const now = new Date();
    const ms = now.getTime() - dt.getTime();
    const days = Math.floor(ms / (24 * 60 * 60 * 1000));
    const hh = String(dt.getHours()).padStart(2, "0");
    const mi = String(dt.getMinutes()).padStart(2, "0");
    if (days >= 0 && days < 7) {
      return `${days}天前 ${hh}:${mi}`;
    }
    return formatShortDateTime(isoText);
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function parseApiDate(isoText) {
    if (!isoText) {
      return new Date(NaN);
    }
    const raw = String(isoText).trim();
    if (!raw) {
      return new Date(NaN);
    }
    const hasTimezone = /[zZ]$|[+-]\d{2}:\d{2}$/.test(raw);
    return new Date(hasTimezone ? raw : `${raw}Z`);
  }

  function formatOneDecimal(value, suffix = "") {
    const n = Number(value);
    if (!Number.isFinite(n)) {
      return "--";
    }
    return `${n.toFixed(1)}${suffix}`;
  }

  function formatRatio(value, digits = 3) {
    const n = Number(value);
    if (!Number.isFinite(n)) {
      return "--";
    }
    return n.toFixed(digits);
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function saveReviewViewerTransform() {
    const v = state.reviews.viewer;
    const payload = {
      scale: Number(v.scale) || 1,
      tx: Number(v.tx) || 0,
      ty: Number(v.ty) || 0,
    };
    try {
      window.localStorage.setItem(REVIEW_VIEWER_CACHE_KEY, JSON.stringify(payload));
    } catch (_err) {
      // ignore storage errors
    }
  }

  function loadReviewViewerTransform() {
    try {
      const raw = window.localStorage.getItem(REVIEW_VIEWER_CACHE_KEY);
      const parsed = raw ? JSON.parse(raw) : {};
      const scale = clamp(Number(parsed?.scale) || 1, state.reviews.viewer.minScale, state.reviews.viewer.maxScale);
      const tx = Number(parsed?.tx) || 0;
      const ty = Number(parsed?.ty) || 0;
      state.reviews.viewer.scale = scale;
      state.reviews.viewer.tx = tx;
      state.reviews.viewer.ty = ty;
    } catch (_err) {
      state.reviews.viewer.scale = 1;
      state.reviews.viewer.tx = 0;
      state.reviews.viewer.ty = 0;
    }
  }

  function resetReviewViewerTransform() {
    state.reviews.viewer.scale = 1;
    state.reviews.viewer.tx = 0;
    state.reviews.viewer.ty = 0;
    saveReviewViewerTransform();
    applyReviewImageTransform();
  }

  function applyReviewImageTransform() {
    const img = el("reviews-image");
    if (!img) {
      return;
    }
    const { scale, tx, ty } = state.reviews.viewer;
    img.style.transform = `translate(-50%, -50%) translate(${tx}px, ${ty}px) scale(${scale})`;
    saveReviewViewerTransform();
  }

  function getReviewImageCandidates(detail) {
    const aiUrl = detail && detail.inference_image_url ? String(detail.inference_image_url) : "";
    const rawUrl = detail && detail.raw_image_url ? String(detail.raw_image_url) : "";
    const fallbackUrl = detail && detail.image_url ? String(detail.image_url) : "";
    return {
      ai: aiUrl || fallbackUrl,
      raw: rawUrl || fallbackUrl,
      hasAi: Boolean(aiUrl),
      hasRaw: Boolean(rawUrl),
    };
  }

  function syncReviewSwitchButton() {
    const btn = document.querySelector(".review-tool-btn[data-review-tool='switch']");
    if (!btn) {
      return;
    }
    const { hasAi, hasRaw, imageSource } = state.reviews.viewer;
    const switchable = hasAi && hasRaw;
    btn.disabled = !switchable;
    btn.classList.toggle("disabled", !switchable);
    btn.classList.toggle("is-active", switchable && imageSource === "raw");
    btn.title = switchable
      ? imageSource === "ai"
        ? "切换到原图"
        : "切换到AI图"
      : "暂无可切换的原图/AI图";
  }

  function updateReviewViewerImage(detail, source = "ai", options = {}) {
    const img = el("reviews-image");
    const empty = el("reviews-empty");
    if (!img || !empty) {
      return;
    }
    const candidates = getReviewImageCandidates(detail);
    let resolvedSource = source === "raw" ? "raw" : "ai";
    if (resolvedSource === "ai" && !candidates.ai && candidates.raw) {
      resolvedSource = "raw";
    } else if (resolvedSource === "raw" && !candidates.raw && candidates.ai) {
      resolvedSource = "ai";
    }
    const imageUrl = resolvedSource === "raw" ? candidates.raw : candidates.ai;
    state.reviews.viewer.imageSource = resolvedSource;
    state.reviews.viewer.hasAi = candidates.hasAi;
    state.reviews.viewer.hasRaw = candidates.hasRaw;
    syncReviewSwitchButton();
    if (!imageUrl) {
      img.removeAttribute("src");
      empty.textContent = "影像不可用";
      empty.style.display = "grid";
      return;
    }
    const keepTransform = Boolean(options && options.keepTransform);
    const nextUrl = String(imageUrl);
    const prevUrl = String(img.getAttribute("src") || "");
    if (prevUrl !== nextUrl) {
      if (keepTransform) {
        img.addEventListener(
          "load",
          () => {
            applyReviewImageTransform();
          },
          { once: true }
        );
      }
      img.src = nextUrl;
    }
    empty.style.display = "none";
    if (keepTransform) {
      applyReviewImageTransform();
    } else {
      resetReviewViewerTransform();
    }
  }

  function getReviewNoteDraft(examId, detail) {
    const id = Number(examId) || 0;
    if (!id) {
      return "";
    }
    if (Object.prototype.hasOwnProperty.call(state.reviews.noteDraftMap, id)) {
      return String(state.reviews.noteDraftMap[id] || "");
    }
    const initial = detail && detail.review_note ? String(detail.review_note) : "";
    state.reviews.noteDraftMap[id] = initial;
    return initial;
  }

  function getChatUnreadTotal() {
    const rows = Array.isArray(state.questionnaires.chats) ? state.questionnaires.chats : [];
    return rows.reduce((acc, row) => acc + Math.max(0, Number(row.unread || 0)), 0);
  }

  function canAccessChatModule() {
    const user = state.user;
    if (!user) {
      return false;
    }
    if (String(user.role || "").toLowerCase() === "admin") {
      return true;
    }
    const modules = Array.isArray(user.module_permissions) ? user.module_permissions : [];
    return modules.includes("chat");
  }

  function scheduleMarkQuestionnaireChatRead(conversationId, delay = 320) {
    const cid = Number(conversationId) || 0;
    if (!cid) {
      return;
    }
    const timers = state.questionnaires.chatReadTimers || {};
    if (timers[cid]) {
      window.clearTimeout(timers[cid]);
    }
    timers[cid] = window.setTimeout(async () => {
      delete timers[cid];
      if (state.activeView !== "chat" || Number(state.questionnaires.chatSelectedId || 0) !== cid) {
        return;
      }
      await markQuestionnaireChatRead(cid);
      renderQuestionnaireChatList();
    }, Math.max(120, Number(delay) || 320));
    state.questionnaires.chatReadTimers = timers;
  }

  function syncRealtimeChatChannelSubscription() {
    const ws = state.realtime.ws;
    const prev = state.questionnaires.realtimeChatChannel || "";
    const cid = Number(state.questionnaires.chatSelectedId || 0);
    const next = state.activeView === "chat" && cid > 0 ? `chat:${cid}` : "";

    if (!ws || ws.readyState !== WebSocket.OPEN) {
      state.questionnaires.realtimeChatChannel = next;
      return;
    }

    if (prev && prev !== next) {
      try {
        ws.send(JSON.stringify({ type: "unsubscribe", channel: prev }));
      } catch (_err) {
        // ignore
      }
    }
    if (next && next !== prev) {
      try {
        ws.send(JSON.stringify({ type: "subscribe", channel: next }));
      } catch (_err) {
        // ignore
      }
    }
    state.questionnaires.realtimeChatChannel = next;
  }

  function handleRealtimeChatMessage(msg) {
    const cid = Number(msg?.conversation_id || msg?.message?.conversation_id || 0);
    const message = msg && typeof msg.message === "object" ? msg.message : null;
    if (!cid || !message) {
      return;
    }

    if (!Array.isArray(state.questionnaires.chatMessagesMap[cid])) {
      state.questionnaires.chatMessagesMap[cid] = [];
    }
    const arr = state.questionnaires.chatMessagesMap[cid];
    const mid = Number(message.id || 0);
    const exists = mid > 0 && arr.some((x) => Number(x.id || 0) === mid);
    if (!exists) {
      arr.push(message);
    }

    const selectedCid = Number(state.questionnaires.chatSelectedId || 0);
    const activeInChat = state.activeView === "chat" && selectedCid === cid;
    let found = false;
    const chats = Array.isArray(state.questionnaires.chats) ? state.questionnaires.chats : [];
    chats.forEach((row) => {
      if (Number(row.id || 0) !== cid) {
        return;
      }
      found = true;
      row.last_message = message;
      row.updated_at = message.created_at || row.updated_at;
      row.unread = activeInChat ? 0 : Math.max(0, Number(row.unread || 0)) + 1;
    });
    if (!found) {
      chats.unshift({
        id: cid,
        name: `会话-${cid}`,
        type: "private",
        patient_id: null,
        updated_at: message.created_at || null,
        unread: activeInChat ? 0 : 1,
        last_message: message,
      });
    }
    chats.sort((a, b) => (parseApiDate(b.updated_at).getTime() || 0) - (parseApiDate(a.updated_at).getTime() || 0));
    state.questionnaires.chats = chats;
    state.questionnaires.chatsLoaded = true;
    renderQuestionnaireChatList();
    if (activeInChat) {
      renderQuestionnaireChatMessages();
      scheduleMarkQuestionnaireChatRead(cid, 180);
    }
  }

  function updateChatUnreadBadges() {
    const total = getChatUnreadTotal();
    const navBadge = el("nav-chat-unread-badge");
    if (navBadge) {
      navBadge.textContent = String(total);
      navBadge.classList.toggle("hidden", total <= 0);
    }
  }

  function renderReviewsList() {
    const host = el("reviews-list");
    if (!host) {
      return;
    }
    host.innerHTML = "";

    const rows = Array.isArray(state.reviews.list) ? state.reviews.list : [];
    if (rows.length === 0) {
      host.innerHTML = '<div class="reviews-empty-list">暂无待复核影像</div>';
      updateReviewViewerImage(null);
      return;
    }

    rows.forEach((row) => {
      const examId = Number(row.id) || 0;
      const isActive = examId === Number(state.reviews.selectedId || 0);
      const detail = state.reviews.detailMap[examId];
      const item = document.createElement("div");
      item.className = "review-item";
      item.dataset.examId = String(examId);
      item.classList.toggle("active", isActive);
      const disabledAttr = state.reviews.submitting ? "disabled" : "";

      let detailHtml = "";
      if (isActive) {
        if (detail) {
          const noteDraft = getReviewNoteDraft(examId, detail);
          const className = String(detail.spine_class || row.spine_class || "").toLowerCase();
          const isCervical = className === "cervical";
          const isPelvis = className === "pelvis";
          const isClavicle = className === "clavicle";
          const cm = detail.cervical_metric && typeof detail.cervical_metric === "object" ? detail.cervical_metric : null;
          const pm = detail.pelvis_metric && typeof detail.pelvis_metric === "object" ? detail.pelvis_metric : null;
          const lm = detail.clavicle_metric && typeof detail.clavicle_metric === "object" ? detail.clavicle_metric : null;
          const metrics = isCervical
            ? [
                {
                  key: "分类",
                  value: detail.spine_class_text || row.spine_class_text || "--",
                },
                { key: "平均左/右比", value: formatRatio(cm?.avg_ratio, 3) },
                { key: "评估", value: cm?.assessment || "--" },
                { key: "有效节段", value: Number.isFinite(Number(cm?.segment_count)) ? String(Number(cm.segment_count)) : "--" },
                { key: "改善值", value: formatRatio(detail.improvement_value, 3) },
              ]
            : isPelvis
              ? [
                  {
                    key: "分类",
                    value: detail.spine_class_text || row.spine_class_text || "--",
                  },
                  { key: "骨盆倾斜角", value: formatOneDecimal(pm?.pelvic_topline_abs_deg ?? pm?.pelvic_topline_deg, "°") },
                  { key: "改善值", value: formatOneDecimal(detail.improvement_value) },
                ]
              : isClavicle
                ? [
                    {
                      key: "分类",
                      value: detail.spine_class_text || row.spine_class_text || "--",
                    },
                    { key: "锁骨倾斜角", value: formatOneDecimal(lm?.clavicle_topline_abs_deg ?? lm?.clavicle_topline_deg, "°") },
                    { key: "T1倾斜角", value: formatOneDecimal(lm?.t1_tilt_abs_deg ?? lm?.t1_tilt_deg, "°") },
                    { key: "改善值", value: formatOneDecimal(detail.improvement_value) },
                  ]
            : [
                {
                  key: "分类",
                  value: detail.spine_class_text || row.spine_class_text || "--",
                },
                { key: "Cobb角", value: formatOneDecimal(detail.cobb_angle, "°") },
                { key: "脊柱曲率", value: formatOneDecimal(detail.curve_value) },
                { key: "严重程度", value: detail.severity_label || "--" },
                { key: "改善值", value: formatOneDecimal(detail.improvement_value) },
              ];
          detailHtml = `
            <div class="review-item-detail">
              ${metrics
                .map(
                  (m) =>
                    `<div class="review-metric-row"><span class="review-metric-key">${escapeHtml(m.key)}</span><span class="review-metric-value">${escapeHtml(m.value)}</span></div>`
                )
                .join("")}
            </div>
            <div class="review-editor">
              <textarea class="review-note-inline" data-review-note-input data-exam-id="${examId}" rows="3" placeholder="复核备注（可选）" ${disabledAttr}>${escapeHtml(noteDraft)}</textarea>
              <div class="review-editor-actions">
                <button type="button" class="review-decision-btn" data-review-action="manual" data-exam-id="${examId}" ${disabledAttr}>
                  <i class="fa-solid fa-pen-ruler"></i>
                  <span>人工</span>
                </button>
                <button type="button" class="review-decision-btn approve" data-review-action="approve" data-exam-id="${examId}" ${disabledAttr}>
                  <i class="fa-solid fa-check"></i>
                  <span>通过</span>
                </button>
              </div>
            </div>
          `;
        } else {
          detailHtml = '<div class="review-item-detail"><div class="review-metric-loading">正在加载AI参数...</div></div>';
        }
      }

      item.innerHTML = `
        <div class="review-item-name-row">
          <div class="review-item-name">${escapeHtml(row.patient_name || "-")}</div>
          <button type="button" class="review-item-delete-btn" data-review-action="delete" data-exam-id="${examId}" title="删除复核例" ${disabledAttr}>
            <i class="fa-solid fa-trash-can"></i>
          </button>
        </div>
        <div class="review-item-date">${escapeHtml(formatDateOnly(row.upload_date))}</div>
        <div class="review-item-type">${escapeHtml(row.spine_class_text || "未分类")}${row.spine_class_confidence !== null && row.spine_class_confidence !== undefined ? ` · ${(Number(row.spine_class_confidence) * 100).toFixed(1)}%` : ""}</div>
        ${detailHtml}
      `;
      host.appendChild(item);
    });
  }

  async function approveReview(examId) {
    const id = Number(examId) || 0;
    if (!id || state.reviews.submitting) {
      return;
    }
    const note = String(state.reviews.noteDraftMap[id] || "").trim();
    state.reviews.submitting = true;
    renderReviewsList();
    try {
      await api(`/api/reviews/${id}/review`, {
        method: "POST",
        body: { decision: "reviewed", note },
      });
      showToast("复核已通过", "success");
      delete state.reviews.detailMap[id];
      delete state.reviews.noteDraftMap[id];
      await loadReviews(true);
    } catch (err) {
      showToast(err.message || "提交复核失败", "error");
    } finally {
      state.reviews.submitting = false;
      renderReviewsList();
    }
  }

  function closeReviewDeleteModal() {
    const modal = el("review-delete-modal");
    if (modal) {
      modal.classList.add("hidden");
    }
    state.reviews.deletingId = null;
  }

  function reviewSpineClassText(className) {
    const key = String(className || "").toLowerCase();
    if (key === "cervical") {
      return "颈椎";
    }
    if (key === "lumbar") {
      return "腰椎";
    }
    if (key === "pelvis") {
      return "骨盆";
    }
    if (key === "clavicle") {
      return "锁骨/T1";
    }
    return "未分类";
  }

  function closeReviewReclassifyModal() {
    const modal = el("review-reclassify-modal");
    const select = el("review-reclassify-class-select");
    if (modal) {
      modal.classList.add("hidden");
    }
    if (select) {
      select.value = "";
    }
    state.reviews.reclassifyId = null;
  }

  function openReviewReclassifyModal(examId) {
    const id = Number(examId) || 0;
    if (!id || state.reviews.submitting) {
      return;
    }
    const modal = el("review-reclassify-modal");
    const text = el("review-reclassify-modal-text");
    const select = el("review-reclassify-class-select");
    if (!modal || !text || !select) {
      return;
    }
    const row = (Array.isArray(state.reviews.list) ? state.reviews.list : []).find((item) => Number(item.id) === id);
    const pname = row?.patient_name || "该患者";
    text.textContent = `请选择 ${pname} 的分类方案后重新推理。此操作不会调用 AI 自动分类。`;
    select.value = "";
    state.reviews.reclassifyId = id;
    modal.classList.remove("hidden");
  }

  async function confirmReviewReclassify() {
    const id = Number(state.reviews.reclassifyId || 0) || 0;
    if (!id || state.reviews.submitting) {
      closeReviewReclassifyModal();
      return;
    }
    const select = el("review-reclassify-class-select");
    const manualSpineClass = String(select?.value || "").trim();
    if (!manualSpineClass) {
      showToast("请选择分类方案", "warn");
      select?.focus();
      return;
    }

    closeReviewReclassifyModal();
    state.reviews.submitting = true;
    renderReviewsList();
    try {
      await api(`/api/reviews/${id}/reclassify`, {
        method: "POST",
        body: { manual_spine_class: manualSpineClass },
      });
      delete state.reviews.detailMap[id];
      showToast(`已按 ${reviewSpineClassText(manualSpineClass)} 重新推理`, "success");
      await loadReviews(true);
    } catch (err) {
      showToast(err.message || "重推理失败", "error");
    } finally {
      state.reviews.submitting = false;
      renderReviewsList();
    }
  }

  function openReviewDeleteModal(examId) {
    const id = Number(examId) || 0;
    if (!id || state.reviews.submitting) {
      return;
    }
    const modal = el("review-delete-modal");
    const text = el("review-delete-modal-text");
    if (!modal || !text) {
      return;
    }
    const row = (Array.isArray(state.reviews.list) ? state.reviews.list : []).find((item) => Number(item.id) === id);
    const pname = row?.patient_name || "该患者";
    text.textContent = `确认删除 ${pname} 的复核例？删除后不可恢复。`;
    state.reviews.deletingId = id;
    modal.classList.remove("hidden");
  }

  async function confirmDeleteReview() {
    const id = Number(state.reviews.deletingId || 0) || 0;
    if (!id || state.reviews.submitting) {
      closeReviewDeleteModal();
      return;
    }
    state.reviews.submitting = true;
    renderReviewsList();
    try {
      await api(`/api/reviews/${id}`, { method: "DELETE" });
      showToast("复核记录已删除", "success");
      delete state.reviews.detailMap[id];
      delete state.reviews.noteDraftMap[id];
      if (Number(state.reviews.selectedId || 0) === id) {
        state.reviews.selectedId = null;
      }
      closeReviewDeleteModal();
      await loadReviews(true);
    } catch (err) {
      showToast(err.message || "删除复核记录失败", "error");
    } finally {
      state.reviews.submitting = false;
      renderReviewsList();
    }
  }

  async function loadReviewDetail(examId, force = false) {
    const id = Number(examId) || 0;
    if (!id) {
      return null;
    }
    if (!force && state.reviews.detailMap[id]) {
      return state.reviews.detailMap[id];
    }
    const data = await api(`/api/reviews/${id}`);
    const detail = data && data.exam ? data.exam : null;
    if (detail) {
      state.reviews.detailMap[id] = detail;
    }
    return detail;
  }

  async function selectReview(examId, options = {}) {
    const id = Number(examId) || 0;
    if (!id) {
      return;
    }
    const preserveTransform =
      options && Object.prototype.hasOwnProperty.call(options, "preserveTransform")
        ? Boolean(options.preserveTransform)
        : true;
    const openMobileDetail =
      options && Object.prototype.hasOwnProperty.call(options, "openMobileDetail")
        ? Boolean(options.openMobileDetail)
        : true;
    state.reviews.selectedId = id;
    state.reviews.viewer.imageSource = "ai";
    if (isMobile() && openMobileDetail) {
      state.reviews.mobileDetailOpen = true;
    }
    syncReviewsMobileView();
    renderReviewsList();
    try {
      const detail = await loadReviewDetail(id, Boolean(options.force));
      renderReviewsList();
      updateReviewViewerImage(detail, "ai", { keepTransform: preserveTransform });
      syncReviewsMobileView();
    } catch (err) {
      updateReviewViewerImage(null);
      syncReviewsMobileView();
      showToast(err.message || "加载复核详情失败", "error");
    }
  }

  async function loadReviews(force = false) {
    if (state.reviews.loading) {
      return;
    }
    if (!force && state.reviews.loaded) {
      renderReviewsList();
      if (state.reviews.selectedId) {
        const cached = state.reviews.detailMap[state.reviews.selectedId];
        if (cached) {
          updateReviewViewerImage(cached, state.reviews.viewer.imageSource || "ai", { keepTransform: true });
        }
      }
      syncReviewsMobileView();
      return;
    }
    state.reviews.loading = true;
    try {
      const data = await api("/api/reviews?status=pending_review");
      state.reviews.list = Array.isArray(data.items) ? data.items : [];
      state.reviews.loaded = true;

      const hasSelected = state.reviews.list.some((r) => Number(r.id) === Number(state.reviews.selectedId));
      if (!hasSelected) {
        state.reviews.selectedId = state.reviews.list.length > 0 ? Number(state.reviews.list[0].id) : null;
      }
      if (!state.reviews.selectedId) {
        state.reviews.mobileDetailOpen = false;
      }
      renderReviewsList();
      if (state.reviews.selectedId) {
        await selectReview(state.reviews.selectedId, { preserveTransform: true, openMobileDetail: false });
      } else {
        updateReviewViewerImage(null);
      }
      syncReviewsMobileView();
    } catch (err) {
      state.reviews.list = [];
      state.reviews.mobileDetailOpen = false;
      renderReviewsList();
      syncReviewsMobileView();
      showToast(err.message || "加载复核列表失败", "error");
    } finally {
      state.reviews.loading = false;
    }
  }

  function renderQuestionnaireHistoryList() {
    const host = el("questionnaires-history-list");
    if (!host) {
      return;
    }
    const rows = Array.isArray(state.questionnaires.items) ? state.questionnaires.items : [];
    if (!rows.length) {
      host.innerHTML = '<div class="questionnaire-history-empty">暂无历史问卷</div>';
      return;
    }
    host.innerHTML = rows
      .map((q) => {
        const statusText = q.status === "active" ? "进行中" : q.status === "closed" ? "已关闭" : q.status || "-";
        const meta = `状态：${statusText} · 回收 ${Number(q.response_count || 0)} · 分配 ${Number(q.assignment_count || 0)}`;
        return `
          <article class="questionnaire-history-item" data-questionnaire-id="${Number(q.id) || 0}">
            <div class="questionnaire-history-title">${escapeHtml(q.title || "未命名问卷")}</div>
            <div class="questionnaire-history-meta">${escapeHtml(meta)}</div>
            <div class="questionnaire-history-meta">${escapeHtml(formatShortDateTime(q.updated_at || q.created_at))}</div>
          </article>
        `;
      })
      .join("");
  }

  function renderQuestionnaireChatList() {
    const host = el("questionnaires-chat-list");
    if (!host) {
      return;
    }
    if (state.questionnaires.directoryMode) {
      updateChatUnreadBadges();
      const keyword = String(state.questionnaires.directoryKeyword || "").trim().toLowerCase();
      const allRows = Array.isArray(state.questionnaires.directoryItems) ? state.questionnaires.directoryItems : [];
      const rows = keyword
        ? allRows.filter((row) => {
            const nm = String(row.name || "").toLowerCase();
            const idText = String(row.id || "");
            return nm.includes(keyword) || idText.includes(keyword);
          })
        : allRows;
      if (!rows.length) {
        host.innerHTML = `<div class="questionnaire-history-empty">${keyword ? "没有匹配用户" : "暂无可选用户"}</div>`;
        return;
      }
      host.innerHTML = rows
        .map((row) => {
          const kind = String(row.kind || "doctor");
          const name = escapeHtml(row.name || "-");
          const meta =
            kind === "patient"
              ? `患者ID ${Number(row.id) || 0}`
              : `医生ID ${Number(row.id) || 0} · ${escapeHtml(row.role || "user")}`;
          return `
            <article class="questionnaires-chat-item" data-dir-kind="${escapeHtml(kind)}" data-dir-id="${Number(row.id) || 0}">
              <div class="questionnaires-chat-item-name">${name}</div>
              <div class="questionnaires-chat-item-meta">${meta}</div>
            </article>
          `;
        })
        .join("");
      host.scrollTop = 0;
      return;
    }
    const rows = Array.isArray(state.questionnaires.chats) ? state.questionnaires.chats : [];
    if (!rows.length) {
      host.innerHTML = '<div class="questionnaire-history-empty">暂无聊天会话</div>';
      updateChatUnreadBadges();
      return;
    }
    host.innerHTML = rows
      .map((row) => {
        const cid = Number(row.id) || 0;
        const isActive = cid === Number(state.questionnaires.chatSelectedId || 0);
        const last = row.last_message && typeof row.last_message === "object" ? row.last_message : null;
        const preview = last ? (last.content || `[${last.message_type || "msg"}]`) : "暂无消息";
        const unread = Number(row.unread || 0);
        return `
          <article class="questionnaires-chat-item ${isActive ? "active" : ""}" data-chat-id="${cid}">
            <div class="questionnaires-chat-item-name">
              <span>${escapeHtml(row.name || `会话-${cid}`)}</span>
              ${unread > 0 ? `<span class="chat-unread-badge chat-row-unread">${unread}</span>` : ""}
            </div>
            <div class="questionnaires-chat-item-meta">${escapeHtml(preview)}</div>
          </article>
        `;
      })
      .join("");
    updateChatUnreadBadges();
  }

  function syncQuestionnaireChatDirectoryUI() {
    const searchRow = el("questionnaires-chat-search-row");
    const queryBtn = el("questionnaires-chat-query-btn");
    searchRow?.classList.toggle("hidden", !state.questionnaires.directoryMode);
    if (queryBtn) {
      queryBtn.classList.toggle("danger", state.questionnaires.directoryMode);
      queryBtn.title = state.questionnaires.directoryMode ? "关闭查询" : "查询用户";
      queryBtn.innerHTML = state.questionnaires.directoryMode
        ? '<i class="fa-solid fa-xmark"></i>'
        : '<i class="fa-solid fa-magnifying-glass"></i>';
    }
  }

  function syncQuestionnaireChatMobileView() {
    const view = el("questionnaires-chat-view");
    const backBtn = el("questionnaires-chat-back-btn");
    if (!view) {
      return;
    }
    const selected = Number(state.questionnaires.chatSelectedId || 0) > 0;
    const mobileDetailOpen =
      isMobile() &&
      selected &&
      !state.questionnaires.directoryMode &&
      Boolean(state.questionnaires.chatMobileDetailOpen);

    view.classList.toggle("mobile-detail-open", mobileDetailOpen);
    if (backBtn) {
      backBtn.classList.toggle("hidden", !mobileDetailOpen);
      backBtn.disabled = !mobileDetailOpen;
    }
  }

  function syncReviewsMobileView() {
    const panel = el("reviews-panel");
    const backBtn = el("reviews-mobile-back-btn");
    if (!panel) {
      return;
    }
    const selected = Number(state.reviews.selectedId || 0) > 0;
    const mobileDetailOpen = isMobile() && selected && Boolean(state.reviews.mobileDetailOpen);
    panel.classList.toggle("mobile-detail-open", mobileDetailOpen);
    if (backBtn) {
      backBtn.classList.toggle("hidden", !mobileDetailOpen);
      backBtn.disabled = !mobileDetailOpen;
    }
  }

  async function loadQuestionnaireDirectory(force = false) {
    if (state.questionnaires.directoryLoading) {
      return;
    }
    if (!force && state.questionnaires.directoryLoaded) {
      renderQuestionnaireChatList();
      return;
    }
    state.questionnaires.directoryLoading = true;
    try {
      const [usersRes, patientsRes] = await Promise.allSettled([api("/api/chat/users"), api("/api/patients")]);
      const userItems =
        usersRes.status === "fulfilled" && Array.isArray(usersRes.value?.items)
          ? usersRes.value.items.map((u) => ({
              kind: "doctor",
              id: Number(u.id) || 0,
              name: u.display_name || u.username || `医生-${u.id}`,
              role: u.role || "user",
            }))
          : [];
      const patientItems =
        patientsRes.status === "fulfilled" && Array.isArray(patientsRes.value?.items)
          ? patientsRes.value.items.map((p) => ({
              kind: "patient",
              id: Number(p.id) || 0,
              name: p.name || `患者-${p.id}`,
              role: "patient",
            }))
          : [];
      state.questionnaires.directoryItems = [...userItems, ...patientItems]
        .filter((i) => Number(i.id) > 0)
        .sort((a, b) => {
          const n = String(a.name || "").localeCompare(String(b.name || ""), "zh-CN");
          if (n !== 0) {
            return n;
          }
          return Number(a.id || 0) - Number(b.id || 0);
        });
      state.questionnaires.directoryLoaded = true;
      renderQuestionnaireChatList();
    } catch (err) {
      state.questionnaires.directoryItems = [];
      renderQuestionnaireChatList();
      showToast(err.message || "加载用户目录失败", "error");
    } finally {
      state.questionnaires.directoryLoading = false;
    }
  }

  async function setQuestionnaireChatDirectoryMode(enabled) {
    const on = Boolean(enabled);
    state.questionnaires.directoryMode = on;
    state.questionnaires.chatMobileDetailOpen = false;
    state.questionnaires.directoryKeyword = "";
    const input = el("questionnaires-chat-search-input");
    if (input) {
      input.value = "";
    }
    syncQuestionnaireChatDirectoryUI();
    syncQuestionnaireChatMobileView();
    if (on) {
      await loadQuestionnaireDirectory(false);
      renderQuestionnaireChatTitlebar();
      renderQuestionnaireChatMessages();
      syncQuestionnaireChatMobileView();
      input?.focus();
      return;
    }
    renderQuestionnaireChatList();
    renderQuestionnaireChatTitlebar();
    renderQuestionnaireChatMessages();
    syncQuestionnaireChatMobileView();
  }

  async function startConversationFromDirectory(kind, id) {
    const targetKind = kind === "patient" ? "patient" : "doctor";
    const targetId = Number(id) || 0;
    if (!targetId) {
      return;
    }
    try {
      const body =
        targetKind === "patient"
          ? { type: "patient", patient_id: targetId }
          : { type: "private", target_user_id: targetId };
      const data = await api("/api/chat/conversations", {
        method: "POST",
        body,
      });
      const cid = Number(data?.conversation?.id || 0) || 0;
      await setQuestionnaireChatDirectoryMode(false);
      await loadQuestionnaireChats(true);
      if (cid) {
        await selectQuestionnaireChat(cid);
      }
    } catch (err) {
      showToast(err.message || "创建会话失败", "error");
    }
  }

  function renderQuestionnaireChatMessageBody(msg) {
    const mtype = String(msg?.message_type || "text");
    const payload = msg && typeof msg.payload === "object" ? msg.payload : {};
    if (mtype === "questionnaire_share") {
      const title = String(payload.questionnaire_title || msg?.content || "问卷任务");
      const url = String(payload.share_url || "");
      const safeUrl = escapeHtml(url);
      return `
        <div class="chat-share-card">
          <div class="chat-share-card-title"><i class="fa-solid fa-clipboard-question"></i><span>${escapeHtml(title)}</span></div>
          <a class="chat-share-card-link" href="${safeUrl}" target="_blank" rel="noopener noreferrer">打开问卷</a>
        </div>
      `;
    }
    const content = msg?.content || `[${mtype || "msg"}]`;
    return `<div>${escapeHtml(content)}</div>`;
  }

  function renderQuestionnaireChatMessages() {
    const host = el("questionnaires-chat-messages");
    if (!host) {
      return;
    }
    const cid = Number(state.questionnaires.chatSelectedId || 0);
    if (!cid) {
      host.innerHTML = '<div class="questionnaire-history-empty">请选择左侧聊天好友</div>';
      return;
    }
    if (state.questionnaires.chatMessagesLoading) {
      host.innerHTML = '<div class="questionnaire-history-empty">正在加载消息...</div>';
      return;
    }
    const rows = Array.isArray(state.questionnaires.chatMessagesMap[cid]) ? state.questionnaires.chatMessagesMap[cid] : [];
    if (!rows.length) {
      host.innerHTML = '<div class="questionnaire-history-empty">暂无消息</div>';
      return;
    }
    const now = new Date();
    const barThresholdMs = 5 * 60 * 1000;
    const dayMs = 24 * 60 * 60 * 1000;
    host.innerHTML = rows
      .map((msg, idx) => {
        const self = msg.sender_kind === "user" && Number(msg.sender_user_id) === Number(state.user?.id || 0);
        const curr = parseApiDate(msg.created_at);
        const prev = idx > 0 ? parseApiDate(rows[idx - 1]?.created_at) : new Date(NaN);
        let barHtml = "";
        const shouldShowBar =
          idx === 0 ||
          (Number.isFinite(curr.getTime()) && Number.isFinite(prev.getTime()) && curr.getTime() - prev.getTime() > barThresholdMs);
        if (shouldShowBar && Number.isFinite(curr.getTime())) {
          const gapToNow = now.getTime() - curr.getTime();
          let label = "--:--";
          if (gapToNow > dayMs) {
            label = `${Math.max(1, Math.floor(gapToNow / dayMs))}天前`;
          } else {
            const hh = String(curr.getHours()).padStart(2, "0");
            const mm = String(curr.getMinutes()).padStart(2, "0");
            label = `${hh}:${mm}`;
          }
          barHtml = `<div class="chat-time-divider"><span>${escapeHtml(label)}</span></div>`;
        }
        return `
          ${barHtml}
          <article class="questionnaires-chat-msg ${self ? "self" : ""}">
            ${renderQuestionnaireChatMessageBody(msg)}
          </article>
        `;
      })
      .join("");
    host.scrollTop = host.scrollHeight;
  }

  function getSelectedQuestionnaireChat() {
    const cid = Number(state.questionnaires.chatSelectedId || 0);
    if (!cid) {
      return null;
    }
    const rows = Array.isArray(state.questionnaires.chats) ? state.questionnaires.chats : [];
    return rows.find((row) => Number(row.id) === cid) || null;
  }

  function renderQuestionnaireChatTitlebar() {
    const btn = el("questionnaires-chat-title-btn");
    if (!btn) {
      return;
    }
    const row = getSelectedQuestionnaireChat();
    if (!row) {
      btn.textContent = "请选择聊天对象";
      btn.disabled = true;
      btn.classList.remove("can-jump");
      btn.removeAttribute("data-patient-id");
      return;
    }
    btn.textContent = String(row.name || `会话-${row.id}`);
    const patientId = Number(row.patient_id || 0) || 0;
    if (patientId) {
      btn.disabled = false;
      btn.classList.add("can-jump");
      btn.setAttribute("data-patient-id", String(patientId));
    } else {
      btn.disabled = true;
      btn.classList.remove("can-jump");
      btn.removeAttribute("data-patient-id");
    }
  }

  async function loadQuestionnaireChatMessages(conversationId, force = false) {
    const cid = Number(conversationId) || 0;
    if (!cid) {
      return;
    }
    if (!force && Array.isArray(state.questionnaires.chatMessagesMap[cid])) {
      renderQuestionnaireChatMessages();
      return;
    }
    state.questionnaires.chatMessagesLoading = true;
    renderQuestionnaireChatMessages();
    try {
      const data = await api(`/api/chat/conversations/${cid}/messages`);
      state.questionnaires.chatMessagesMap[cid] = Array.isArray(data.items) ? data.items : [];
    } catch (err) {
      state.questionnaires.chatMessagesMap[cid] = [];
      showToast(err.message || "加载聊天消息失败", "error");
    } finally {
      state.questionnaires.chatMessagesLoading = false;
      renderQuestionnaireChatMessages();
    }
  }

  async function markQuestionnaireChatRead(conversationId) {
    const cid = Number(conversationId) || 0;
    if (!cid) {
      return;
    }
    try {
      await api(`/api/chat/conversations/${cid}/read`, { method: "POST" });
    } catch (_err) {
      // ignore
    }
    const rows = Array.isArray(state.questionnaires.chats) ? state.questionnaires.chats : [];
    rows.forEach((row) => {
      if (Number(row.id) === cid) {
        row.unread = 0;
      }
    });
    updateChatUnreadBadges();
  }

  async function selectQuestionnaireChat(conversationId) {
    const cid = Number(conversationId) || 0;
    if (!cid) {
      return;
    }
    state.questionnaires.chatSelectedId = cid;
    if (isMobile()) {
      state.questionnaires.chatMobileDetailOpen = true;
    }
    syncQuestionnaireChatMobileView();
    renderQuestionnaireChatList();
    renderQuestionnaireChatTitlebar();
    await loadQuestionnaireChatMessages(cid, false);
    await markQuestionnaireChatRead(cid);
    syncRealtimeChatChannelSubscription();
    renderQuestionnaireChatList();
    syncQuestionnaireChatMobileView();
  }

  async function loadQuestionnaireChats(force = false) {
    if (state.questionnaires.chatsLoading) {
      return;
    }
    if (!force && state.questionnaires.chatsLoaded) {
      renderQuestionnaireChatList();
      renderQuestionnaireChatTitlebar();
      renderQuestionnaireChatMessages();
      updateChatUnreadBadges();
      syncQuestionnaireChatMobileView();
      return;
    }
    state.questionnaires.chatsLoading = true;
    try {
      const data = await api("/api/chat/conversations");
      state.questionnaires.chats = Array.isArray(data.items) ? data.items : [];
      state.questionnaires.chatsLoaded = true;
      const hasSelected = state.questionnaires.chats.some(
        (row) => Number(row.id) === Number(state.questionnaires.chatSelectedId || 0)
      );
      if (!hasSelected) {
        state.questionnaires.chatSelectedId = null;
        state.questionnaires.chatMobileDetailOpen = false;
      }
      renderQuestionnaireChatList();
      renderQuestionnaireChatTitlebar();
      if (state.questionnaires.chatSelectedId) {
        await loadQuestionnaireChatMessages(state.questionnaires.chatSelectedId, false);
        if (state.activeView === "chat") {
          await markQuestionnaireChatRead(state.questionnaires.chatSelectedId);
        }
      } else {
        renderQuestionnaireChatMessages();
      }
      syncRealtimeChatChannelSubscription();
      syncQuestionnaireChatMobileView();
    } catch (err) {
      state.questionnaires.chats = [];
      state.questionnaires.chatMobileDetailOpen = false;
      renderQuestionnaireChatList();
      renderQuestionnaireChatTitlebar();
      renderQuestionnaireChatMessages();
      syncQuestionnaireChatMobileView();
      showToast(err.message || "加载聊天列表失败", "error");
    } finally {
      state.questionnaires.chatsLoading = false;
      updateChatUnreadBadges();
    }
  }

  async function sendQuestionnaireChatMessage() {
    const cid = Number(state.questionnaires.chatSelectedId || 0);
    const input = el("questionnaires-chat-input");
    if (!cid || !input) {
      return;
    }
    const content = String(input.value || "").trim();
    if (!content) {
      return;
    }
    input.value = "";
    try {
      await api(`/api/chat/conversations/${cid}/messages`, {
        method: "POST",
        body: {
          content,
          message_type: "text",
        },
      });
      await loadQuestionnaireChatMessages(cid, true);
      await loadQuestionnaireChats(true);
    } catch (err) {
      showToast(err.message || "发送失败", "error");
      input.value = content;
    }
  }

  function openQuestionnaireDetailLayer() {
    const layer = el("questionnaires-detail-layer");
    if (!layer) {
      return;
    }
    layer.classList.remove("hidden");
  }

  function closeQuestionnaireDetailLayer() {
    const layer = el("questionnaires-detail-layer");
    if (!layer) {
      return;
    }
    layer.classList.add("hidden");
    closeQuestionnaireAssignModal();
    closeQuestionnaireDetailSettingsModal();
    state.questionnaires.detailId = null;
    state.questionnaires.detail = null;
  }

  function closeQuestionnaireAssignModal() {
    const modal = el("questionnaire-assign-modal");
    if (!modal) {
      return;
    }
    modal.classList.add("hidden");
    state.questionnaires.assignModalOpen = false;
  }

  function getFilteredQuestionnaireAssignCandidates() {
    const rows = Array.isArray(state.questionnaires.assignCandidates) ? state.questionnaires.assignCandidates : [];
    const keyword = String(state.questionnaires.assignSearch || "").trim().toLowerCase();
    if (!keyword) {
      return rows;
    }
    return rows.filter((row) => {
      const name = String(row.name || "").toLowerCase();
      const sid = String(Number(row.id) || 0);
      return name.includes(keyword) || sid.includes(keyword);
    });
  }

  function renderQuestionnaireAssignList() {
    const list = el("questionnaire-assign-list");
    const count = el("questionnaire-assign-selected-count");
    const submit = el("questionnaire-assign-submit-btn");
    if (!list || !count || !submit) {
      return;
    }
    const selected = new Set((state.questionnaires.assignSelectedIds || []).map((x) => Number(x) || 0).filter((x) => x > 0));
    const rows = getFilteredQuestionnaireAssignCandidates();
    count.textContent = `已选 ${selected.size} 人`;
    submit.disabled = state.questionnaires.assignSubmitting || selected.size === 0;
    if (state.questionnaires.assignLoading) {
      list.innerHTML = '<div class="questionnaire-history-empty">正在加载患者列表...</div>';
      return;
    }
    if (!rows.length) {
      list.innerHTML = '<div class="questionnaire-history-empty">没有匹配患者</div>';
      return;
    }
    list.innerHTML = rows
      .map((row) => {
        const pid = Number(row.id) || 0;
        const isSelected = selected.has(pid);
        const statusText = String(row.status_text || "随访中");
        const nextFollowupText = row.next_followup_at ? ` · 下次随访 ${formatDateOnly(row.next_followup_at)}` : "";
        return `
          <div class="questionnaire-assign-item ${isSelected ? "selected" : ""}" data-patient-id="${pid}">
            <div class="questionnaire-assign-item-left">
              <div class="questionnaire-assign-item-name">${escapeHtml(row.name || `患者-${pid}`)}</div>
              <div class="questionnaire-assign-item-meta">患者ID ${pid} · ${escapeHtml(statusText)}${escapeHtml(nextFollowupText)}</div>
            </div>
            <input type="checkbox" data-patient-checkbox data-patient-id="${pid}" ${isSelected ? "checked" : ""} />
          </div>
        `;
      })
      .join("");
  }

  async function loadQuestionnaireAssignCandidates() {
    state.questionnaires.assignLoading = true;
    renderQuestionnaireAssignList();
    try {
      const perPage = 100;
      let page = 1;
      let hasMore = true;
      const allPatients = [];
      while (hasMore && page <= 50) {
        const data = await api(`/api/patients?page=${page}&per_page=${perPage}`);
        const rows = Array.isArray(data.items) ? data.items : [];
        allPatients.push(...rows);
        hasMore = Boolean(data.has_more) && rows.length > 0;
        page += 1;
      }

      const uniqueMap = new Map();
      allPatients.forEach((p) => {
        const pid = Number(p.id) || 0;
        if (!pid || uniqueMap.has(pid)) {
          return;
        }
        uniqueMap.set(pid, {
          id: pid,
          name: p.name || `患者-${pid}`,
          status_text: p.status_text || "随访中",
          next_followup_at: p.next_followup_at || null,
          updated_at: p.updated_at || null,
        });
      });
      state.questionnaires.assignCandidates = [...uniqueMap.values()];
    } catch (err) {
      state.questionnaires.assignCandidates = [];
      showToast(err.message || "加载患者列表失败", "error");
    } finally {
      state.questionnaires.assignLoading = false;
      renderQuestionnaireAssignList();
    }
  }

  async function openQuestionnaireAssignModal() {
    const qid = Number(state.questionnaires.detailId || 0) || 0;
    if (!qid) {
      showToast("问卷未加载", "error");
      return;
    }
    const modal = el("questionnaire-assign-modal");
    const input = el("questionnaire-assign-search-input");
    if (!modal || !input) {
      return;
    }
    state.questionnaires.assignModalOpen = true;
    state.questionnaires.assignSubmitting = false;
    state.questionnaires.assignSearch = "";
    state.questionnaires.assignSelectedIds = [];
    input.value = "";
    modal.classList.remove("hidden");
    renderQuestionnaireAssignList();
    await loadQuestionnaireAssignCandidates();
    input.focus();
  }

  async function submitQuestionnaireAssign() {
    if (state.questionnaires.assignSubmitting) {
      return;
    }
    const qid = Number(state.questionnaires.detailId || 0) || 0;
    if (!qid) {
      return;
    }
    const ids = [...new Set((state.questionnaires.assignSelectedIds || []).map((x) => Number(x) || 0).filter((x) => x > 0))];
    if (!ids.length) {
      showToast("请至少选择一位患者", "error");
      return;
    }
    state.questionnaires.assignSubmitting = true;
    renderQuestionnaireAssignList();
    try {
      const data = await api(`/api/questionnaires/${qid}/assign`, {
        method: "POST",
        body: { patient_ids: ids },
      });
      showToast(data?.message || `已发送 ${ids.length} 份`, "success");
      closeQuestionnaireAssignModal();
      await loadQuestionnaireDetail(qid);
      await loadQuestionnaires(true);
    } catch (err) {
      showToast(err.message || "发送问卷失败", "error");
    } finally {
      state.questionnaires.assignSubmitting = false;
      renderQuestionnaireAssignList();
    }
  }

  function toLocalInputDateTime(isoValue) {
    if (!isoValue) {
      return "";
    }
    const d = new Date(isoValue);
    if (Number.isNaN(d.getTime())) {
      return "";
    }
    const pad = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  function fromLocalInputDateTime(localValue) {
    const raw = String(localValue || "").trim();
    if (!raw) {
      return null;
    }
    const d = new Date(raw);
    if (Number.isNaN(d.getTime())) {
      return null;
    }
    return d.toISOString();
  }

  function renderQuestionnaireDistributionPie(item, options) {
    const dist = item && typeof item.distribution === "object" ? item.distribution : {};
    const labels = (Array.isArray(options) ? options : []).map((x) => String(x));
    const keys = labels.length ? labels : Object.keys(dist || {});
    const values = keys.map((k) => Math.max(0, Number(dist[k]) || 0));
    const total = values.reduce((sum, n) => sum + n, 0);
    if (!total) {
      return '<div class="qd-pie-empty">暂无样本</div>';
    }
    const colors = ["#3b82f6", "#22c55e", "#f59e0b", "#a78bfa", "#f97316"];
    let cursor = 0;
    const segments = values
      .map((v, idx) => {
        const start = (cursor / total) * 360;
        cursor += v;
        const end = (cursor / total) * 360;
        return `${colors[idx % colors.length]} ${start}deg ${end}deg`;
      })
      .join(", ");
    const legend = keys
      .map((k, idx) => {
        const percent = ((values[idx] / total) * 100).toFixed(1);
        return `<li><span class="dot" style="background:${colors[idx % colors.length]}"></span><span>${escapeHtml(k)} · ${percent}%</span></li>`;
      })
      .join("");
    return `
      <div class="qd-pie-wrap">
        <div class="qd-pie" style="background:conic-gradient(${segments})"></div>
        <ul class="qd-pie-legend">${legend}</ul>
      </div>
    `;
  }

  function renderQuestionnaireDetail() {
    const content = el("questionnaire-detail-content");
    const stats = el("questionnaire-detail-stats");
    if (!content || !stats) {
      return;
    }
    if (state.questionnaires.detailLoading) {
      content.innerHTML = '<div class="questionnaire-history-empty">正在加载问卷详情...</div>';
      stats.innerHTML = "";
      return;
    }
    const detail = state.questionnaires.detail;
    if (!detail || !detail.questionnaire) {
      content.innerHTML = '<div class="questionnaire-history-empty">暂无详情</div>';
      stats.innerHTML = "";
      return;
    }
    const q = detail.questionnaire;
    const questions = Array.isArray(q.questions) ? q.questions : [];
    const statsMap = new Map((Array.isArray(q.stats) ? q.stats : []).map((s) => [Number(s.question_id) || 0, s]));
    const statusText = q.status === "active" ? "进行中" : q.status === "closed" ? "已关闭" : q.status || "-";
    content.innerHTML = `
      <section class="questionnaire-detail-head">
        <div class="questionnaire-field">
          <span>问卷标题</span>
          <input id="questionnaire-detail-title-input" type="text" value="${escapeHtml(q.title || "")}" placeholder="请输入问卷标题">
        </div>
        <div class="questionnaire-detail-meta">状态：${escapeHtml(statusText)} · 更新时间：${escapeHtml(formatShortDateTime(q.updated_at || q.created_at))}</div>
      </section>
      <section class="questionnaire-detail-intro">
        <label class="questionnaire-field">
          <span>问卷简介</span>
          <textarea id="questionnaire-detail-description-input" rows="5" placeholder="请输入问卷简介">${escapeHtml(q.description || "")}</textarea>
        </label>
      </section>
      ${questions.length
        ? questions
            .map((item, idx) => {
              const qType = item.q_type === "text" ? "填空题" : item.q_type === "multi" ? "多选题" : "单选题";
              const options = Array.isArray(item.options) ? item.options : [];
              const qStat = statsMap.get(Number(item.id) || 0);
              return `
                <article class="questionnaire-detail-question" data-detail-qid="${Number(item.id) || 0}">
                  <div class="questionnaire-detail-question-main">
                    <div class="questionnaire-detail-question-head">
                      <span class="questionnaire-detail-question-meta">第 ${idx + 1} 题 · ${escapeHtml(qType)}</span>
                      <button type="button" class="questionnaire-q-remove" data-detail-action="remove-question" data-q-id="${Number(item.id) || 0}" title="删除题目">
                        <i class="fa-solid fa-trash"></i>
                      </button>
                    </div>
                    <label class="questionnaire-field">
                      <span>题目</span>
                      <input type="text" data-detail-action="title" data-q-id="${Number(item.id) || 0}" value="${escapeHtml(item.title || "")}" placeholder="请输入题目标题">
                    </label>
                    <div class="questionnaire-detail-question-options">
                      ${
                        item.q_type === "text"
                          ? `<span>填写约束：${escapeHtml(questionnaireConstraintLabel(item.constraint || "any"))}${item.constraint_hint ? ` · ${escapeHtml(item.constraint_hint)}` : ""}</span>`
                          : (options.length ? options : ["-"])
                              .map(
                                (opt, oi) => `
                                  <label class="questionnaire-detail-option-row">
                                    <input type="text" data-detail-action="option" data-q-id="${Number(item.id) || 0}" data-opt-index="${oi}" value="${escapeHtml(opt)}">
                                    <button type="button" class="questionnaire-q-remove" data-detail-action="remove-option" data-q-id="${Number(item.id) || 0}" data-opt-index="${oi}" title="删除选项">
                                      <i class="fa-solid fa-xmark"></i>
                                    </button>
                                  </label>
                                `
                              )
                              .join("")
                      }
                    </div>
                  </div>
                  ${
                    item.q_type === "text"
                      ? ""
                      : `<aside class="questionnaire-detail-question-stat">${renderQuestionnaireDistributionPie(qStat, options)}</aside>`
                  }
                </article>
              `;
            })
            .join("")
        : '<div class="questionnaire-history-empty">暂无题目</div>'}
    `;
    const completed = Number(q.completed_count || 0);
    const pending = Number(q.pending_count || 0);
    const total = Number(q.assignment_count || 0);
    const finishRate = total > 0 ? `${((completed / total) * 100).toFixed(1)}%` : "0.0%";
    stats.innerHTML = `
      <article class="questionnaire-detail-metric-card">
        <div class="label">已完成</div>
        <div class="value">${Number.isFinite(completed) ? completed : 0}</div>
      </article>
      <article class="questionnaire-detail-metric-card">
        <div class="label">待完成</div>
        <div class="value">${Number.isFinite(pending) ? pending : 0}</div>
      </article>
      <article class="questionnaire-detail-metric-card">
        <div class="label">完成率</div>
        <div class="value">${finishRate}</div>
      </article>
      <article class="questionnaire-detail-metric-card">
        <div class="label">总分配</div>
        <div class="value">${Number.isFinite(total) ? total : 0}</div>
      </article>
    `;
  }

  async function loadQuestionnaireDetail(questionnaireId) {
    const qid = Number(questionnaireId) || 0;
    if (!qid) {
      return;
    }
    state.questionnaires.detailId = qid;
    state.questionnaires.detailLoading = true;
    state.questionnaires.detail = null;
    openQuestionnaireDetailLayer();
    renderQuestionnaireDetail();
    try {
      const data = await api(`/api/questionnaires/${qid}`);
      state.questionnaires.detail = data;
      const questionnaire = state.questionnaires.detail?.questionnaire;
      if (questionnaire) {
        questionnaire.allow_non_patient = Boolean(questionnaire.allow_non_patient);
        questionnaire.questions = (Array.isArray(questionnaire.questions) ? questionnaire.questions : []).map((item) => ({
          ...item,
          options: Array.isArray(item.options) ? item.options : [],
          constraint: item.constraint || "any",
          constraint_hint: item.constraint_hint || "",
        }));
      }
    } catch (err) {
      showToast(err.message || "加载问卷详情失败", "error");
      state.questionnaires.detail = null;
    } finally {
      state.questionnaires.detailLoading = false;
      renderQuestionnaireDetail();
    }
  }

  function closeQuestionnaireDetailSettingsModal() {
    const modal = el("questionnaire-detail-settings-modal");
    if (modal) {
      modal.classList.add("hidden");
    }
    state.questionnaires.detailSettingsOpen = false;
  }

  function openQuestionnaireDetailSettingsModal() {
    const modal = el("questionnaire-detail-settings-modal");
    if (!modal || !state.questionnaires.detail?.questionnaire) {
      return;
    }
    const q = state.questionnaires.detail.questionnaire;
    const allowSelect = el("questionnaire-detail-allow-public");
    const openFromInput = el("questionnaire-detail-open-from");
    const openUntilInput = el("questionnaire-detail-open-until");
    if (allowSelect) {
      allowSelect.value = q.allow_non_patient ? "1" : "0";
    }
    if (openFromInput) {
      openFromInput.value = toLocalInputDateTime(q.open_from);
    }
    if (openUntilInput) {
      openUntilInput.value = toLocalInputDateTime(q.open_until);
    }
    modal.classList.remove("hidden");
    state.questionnaires.detailSettingsOpen = true;
  }

  function applyQuestionnaireDetailSettingsFromModal() {
    const q = state.questionnaires.detail?.questionnaire;
    if (!q) {
      return;
    }
    const allowSelect = el("questionnaire-detail-allow-public");
    const openFromInput = el("questionnaire-detail-open-from");
    const openUntilInput = el("questionnaire-detail-open-until");
    q.allow_non_patient = String(allowSelect?.value || "0") === "1";
    q.open_from = fromLocalInputDateTime(openFromInput?.value || "");
    q.open_until = fromLocalInputDateTime(openUntilInput?.value || "");
  }

  function buildQuestionnaireDetailSavePayload() {
    const detail = state.questionnaires.detail;
    const q = detail?.questionnaire;
    if (!q) {
      throw new Error("问卷详情不存在");
    }
    const title = String(q.title || "").trim();
    if (!title) {
      throw new Error("问卷标题不能为空");
    }
    const questions = Array.isArray(q.questions) ? q.questions : [];
    if (!questions.length) {
      throw new Error("至少保留一个题目");
    }
    return {
      title,
      description: String(q.description || ""),
      allow_non_patient: Boolean(q.allow_non_patient),
      open_from: q.open_from || null,
      open_until: q.open_until || null,
      questions: questions.map((item, idx) => {
        const qTitle = String(item.title || "").trim();
        if (!qTitle) {
          throw new Error(`第 ${idx + 1} 题标题不能为空`);
        }
        if (item.q_type === "text") {
          return {
            id: Number(item.id) || 0,
            q_type: "text",
            title: qTitle,
            options: [
              {
                constraint: String(item.constraint || "any"),
                constraint_hint: String(item.constraint_hint || ""),
              },
            ],
          };
        }
        const opts = (Array.isArray(item.options) ? item.options : []).map((x) => String(x || "").trim()).filter((x) => Boolean(x));
        if (opts.length < 2) {
          throw new Error(`第 ${idx + 1} 题至少保留2个选项`);
        }
        return {
          id: Number(item.id) || 0,
          q_type: item.q_type === "multi" ? "multi" : "single",
          title: qTitle,
          options: opts,
        };
      }),
    };
  }

  async function saveQuestionnaireDetail() {
    const qid = Number(state.questionnaires.detailId || 0) || 0;
    if (!qid || state.questionnaires.saving) {
      return;
    }
    try {
      const payload = buildQuestionnaireDetailSavePayload();
      state.questionnaires.saving = true;
      await api(`/api/questionnaires/${qid}/safe-edit`, { method: "PATCH", body: payload });
      showToast("问卷修改已保存", "success");
      await loadQuestionnaireDetail(qid);
      await loadQuestionnaires(true);
    } catch (err) {
      showToast(err.message || "保存失败", "error");
    } finally {
      state.questionnaires.saving = false;
    }
  }

  async function loadQuestionnaires(force = false) {
    if (state.questionnaires.loading) {
      return;
    }
    if (!force && state.questionnaires.loaded) {
      renderQuestionnaireHistoryList();
      return;
    }
    state.questionnaires.loading = true;
    try {
      const data = await api("/api/questionnaires");
      state.questionnaires.items = Array.isArray(data.items) ? data.items : [];
      state.questionnaires.loaded = true;
      renderQuestionnaireHistoryList();
    } catch (err) {
      state.questionnaires.items = [];
      renderQuestionnaireHistoryList();
      showToast(err.message || "加载历史问卷失败", "error");
    } finally {
      state.questionnaires.loading = false;
    }
  }

  function openQuestionnaireCreateLayer() {
    const layer = el("questionnaires-create-layer");
    if (!layer) {
      return;
    }
    layer.classList.remove("hidden");
    closeQuestionnaireDetailLayer();
    state.questionnaires.createMode = true;
  }

  function closeQuestionnaireCreateLayer() {
    const layer = el("questionnaires-create-layer");
    if (!layer) {
      return;
    }
    layer.classList.add("hidden");
    state.questionnaires.createMode = false;
    closeQuestionnaireSettingModal();
  }

  function ensureQuestionnaireDraft() {
    if (!state.questionnaires.draft || typeof state.questionnaires.draft !== "object") {
      state.questionnaires.draft = { title: "", introHtml: "", questions: [], nextId: 1 };
    }
    if (!Array.isArray(state.questionnaires.draft.questions)) {
      state.questionnaires.draft.questions = [];
    }
    if (!Number.isFinite(state.questionnaires.draft.nextId) || state.questionnaires.draft.nextId < 1) {
      state.questionnaires.draft.nextId = 1;
    }
  }

  function questionnaireConstraintLabel(key) {
    const map = {
      any: "任意",
      number: "仅数字",
      letters: "仅字母",
      alnum: "字母+数字",
    };
    return map[key] || "任意";
  }

  function createDraftQuestion(type) {
    ensureQuestionnaireDraft();
    const id = state.questionnaires.draft.nextId++;
    if (type === "blank") {
      return {
        id,
        type: "blank",
        title: "",
        constraint: "any",
        constraint_hint: "",
      };
    }
    return {
      id,
      type: "choice",
      title: "",
      options: ["选项1", "选项2"],
    };
  }

  function addDraftQuestion(type) {
    const t = type === "blank" ? "blank" : "choice";
    ensureQuestionnaireDraft();
    state.questionnaires.draft.questions.push(createDraftQuestion(t));
    renderQuestionnaireBuilder();
  }

  function createQuestionnaireEditorImageWrap(src, altText = "image") {
    const wrap = document.createElement("figure");
    wrap.className = "questionnaire-editor-image-wrap";
    wrap.setAttribute("contenteditable", "false");
    const img = document.createElement("img");
    img.src = String(src || "");
    img.alt = String(altText || "image");
    img.addEventListener("load", () => {
      if (!wrap.style.width) {
        wrap.style.width = `${Math.max(160, Math.min(420, img.naturalWidth || 420))}px`;
      }
    });
    wrap.appendChild(img);
    return wrap;
  }

  function serializeQuestionnaireIntroHtml(editor) {
    if (!editor) {
      return "";
    }
    const clone = editor.cloneNode(true);
    clone.querySelectorAll(".questionnaire-image-tools, .questionnaire-image-handle").forEach((node) => node.remove());
    clone.querySelectorAll(".questionnaire-editor-image-wrap").forEach((node) => node.classList.remove("selected"));
    return clone.innerHTML || "";
  }

  function normalizeQuestionnaireEditorImages(editor) {
    if (!editor) {
      return;
    }
    editor.querySelectorAll(".questionnaire-image-tools, .questionnaire-image-handle").forEach((node) => node.remove());
    const imgs = Array.from(editor.querySelectorAll("img"));
    imgs.forEach((img) => {
      if (img.closest(".questionnaire-editor-image-wrap")) {
        return;
      }
      const wrap = createQuestionnaireEditorImageWrap(img.getAttribute("src") || "", img.getAttribute("alt") || "image");
      img.replaceWith(wrap);
    });
  }

  function clearQuestionnaireImageSelection(editor) {
    if (!editor) {
      return;
    }
    editor.querySelectorAll(".questionnaire-editor-image-wrap.selected").forEach((node) => {
      node.classList.remove("selected");
      node.querySelectorAll(".questionnaire-image-tools, .questionnaire-image-handle").forEach((tool) => tool.remove());
    });
  }

  function setQuestionnaireImageWidth(editor, wrap, nextWidth) {
    if (!editor || !wrap) {
      return;
    }
    const editorWidth = Math.max(160, editor.clientWidth - 24);
    const width = clamp(Number(nextWidth) || 0, 120, editorWidth);
    wrap.style.width = `${Math.round(width)}px`;
  }

  function attachQuestionnaireImageTools(editor, wrap) {
    if (!editor || !wrap) {
      return;
    }
    wrap.querySelectorAll(".questionnaire-image-tools, .questionnaire-image-handle").forEach((node) => node.remove());
    const tools = document.createElement("div");
    tools.className = "questionnaire-image-tools";
    tools.innerHTML = `
      <button type="button" class="questionnaire-image-tool-btn" data-img-tool="zoom-out" title="缩小"><i class="fa-solid fa-minus"></i></button>
      <button type="button" class="questionnaire-image-tool-btn" data-img-tool="zoom-in" title="放大"><i class="fa-solid fa-plus"></i></button>
      <button type="button" class="questionnaire-image-tool-btn" data-img-tool="reset" title="重置"><i class="fa-solid fa-arrows-rotate"></i></button>
    `;
    const handle = document.createElement("span");
    handle.className = "questionnaire-image-handle";
    handle.setAttribute("data-img-handle", "se");
    wrap.appendChild(tools);
    wrap.appendChild(handle);
  }

  function selectQuestionnaireEditorImage(editor, target) {
    if (!editor || !target) {
      return;
    }
    clearQuestionnaireImageSelection(editor);
    target.classList.add("selected");
    attachQuestionnaireImageTools(editor, target);
  }

  function insertNodeAtCaret(editor, node) {
    if (!editor || !node) {
      return;
    }
    const sel = window.getSelection();
    if (sel && sel.rangeCount > 0) {
      const range = sel.getRangeAt(0);
      const anchor = range.commonAncestorContainer;
      if (!editor.contains(anchor)) {
        editor.appendChild(node);
        return;
      }
      range.deleteContents();
      range.insertNode(node);
      range.setStartAfter(node);
      range.collapse(true);
      sel.removeAllRanges();
      sel.addRange(range);
      return;
    }
    editor.appendChild(node);
  }

  function setQuestionnaireSaveLoading(loading) {
    const btn = el("questionnaire-save-btn");
    if (!btn) {
      return;
    }
    btn.disabled = Boolean(loading);
    state.questionnaires.saving = Boolean(loading);
  }

  function buildQuestionnaireSavePayload() {
    ensureQuestionnaireDraft();
    const draft = state.questionnaires.draft;
    const title = String(draft.title || "").trim();
    const description = String(draft.introHtml || "");
    if (!title) {
      throw new Error("问卷标题必填");
    }
    const questions = [];
    (draft.questions || []).forEach((q, idx) => {
      const qTitle = String(q?.title || "").trim();
      if (!qTitle) {
        throw new Error(`第 ${idx + 1} 题标题不能为空`);
      }
      if (q.type === "blank") {
        questions.push({
          q_type: "text",
          title: qTitle,
          options: [
            {
              constraint: String(q.constraint || "any"),
              constraint_hint: String(q.constraint_hint || ""),
            },
          ],
        });
        return;
      }
      const options = Array.isArray(q.options)
        ? q.options.map((opt) => String(opt || "").trim()).filter((opt) => Boolean(opt))
        : [];
      if (options.length < 2) {
        throw new Error(`第 ${idx + 1} 题至少保留两个选项`);
      }
      questions.push({
        q_type: "single",
        title: qTitle,
        options,
      });
    });
    if (!questions.length) {
      throw new Error("至少添加一个题目");
    }
    return {
      title,
      description,
      questions,
    };
  }

  async function saveQuestionnaireDraft() {
    if (state.questionnaires.saving) {
      return;
    }
    try {
      const payload = buildQuestionnaireSavePayload();
      setQuestionnaireSaveLoading(true);
      await api("/api/questionnaires", { method: "POST", body: payload });
      showToast(`问卷“${payload.title}”已保存`, "success");
      state.questionnaires.draft = {
        title: "",
        introHtml: "",
        questions: [],
        nextId: 1,
      };
      closeQuestionnaireCreateLayer();
      await loadQuestionnaires(true);
    } catch (err) {
      showToast(err.message || "保存问卷失败", "error");
    } finally {
      setQuestionnaireSaveLoading(false);
      renderQuestionnaireBuilder();
    }
  }

  function closeQuestionnaireSettingModal() {
    const modal = el("questionnaire-blank-setting-modal");
    if (modal) {
      modal.classList.add("hidden");
    }
    state.questionnaires.settingQuestionId = null;
  }

  function openQuestionnaireSettingModal(questionId) {
    ensureQuestionnaireDraft();
    const id = Number(questionId) || 0;
    const row = state.questionnaires.draft.questions.find((q) => Number(q.id) === id && q.type === "blank");
    if (!row) {
      return;
    }
    state.questionnaires.settingQuestionId = id;
    const modal = el("questionnaire-blank-setting-modal");
    const select = el("questionnaire-constraint-select");
    const hint = el("questionnaire-constraint-hint");
    if (select) {
      select.value = row.constraint || "any";
    }
    if (hint) {
      hint.value = row.constraint_hint || "";
    }
    modal?.classList.remove("hidden");
  }

  function saveQuestionnaireSettingModal() {
    ensureQuestionnaireDraft();
    const qid = Number(state.questionnaires.settingQuestionId) || 0;
    if (!qid) {
      closeQuestionnaireSettingModal();
      return;
    }
    const row = state.questionnaires.draft.questions.find((q) => Number(q.id) === qid && q.type === "blank");
    if (!row) {
      closeQuestionnaireSettingModal();
      return;
    }
    const select = el("questionnaire-constraint-select");
    const hint = el("questionnaire-constraint-hint");
    row.constraint = (select?.value || "any").trim() || "any";
    row.constraint_hint = (hint?.value || "").trim();
    closeQuestionnaireSettingModal();
    renderQuestionnaireBuilder();
  }

  function renderQuestionnaireBuilder() {
    ensureQuestionnaireDraft();
    const draft = state.questionnaires.draft;
    const titleInput = el("questionnaire-title-input");
    const intro = el("questionnaire-intro-editor");
    const list = el("questionnaire-questions-list");
    if (titleInput && titleInput.value !== String(draft.title || "")) {
      titleInput.value = String(draft.title || "");
    }
    if (intro && intro.innerHTML !== String(draft.introHtml || "")) {
      intro.innerHTML = String(draft.introHtml || "");
    }
    if (intro) {
      normalizeQuestionnaireEditorImages(intro);
    }
    if (!list) {
      return;
    }
    const questionHtml = draft.questions
      .map((q, idx) => {
        const tag = q.type === "blank" ? "填空题" : "选项题";
        const title = escapeHtml(q.title || "");
        const questionHead = `
          <div class="questionnaire-question-head">
            <span class="questionnaire-q-tag">第 ${idx + 1} 题 · ${tag}</span>
            <button type="button" class="questionnaire-q-remove" data-q-action="remove" data-q-id="${q.id}"><i class="fa-solid fa-trash"></i></button>
          </div>
          <label class="questionnaire-field">
            <span>题目标题</span>
            <input type="text" data-q-action="title" data-q-id="${q.id}" value="${title}" placeholder="请输入题目标题">
          </label>
        `;
        if (q.type === "blank") {
          const hint = q.constraint_hint ? ` · ${escapeHtml(q.constraint_hint)}` : "";
          return `
            <article class="questionnaire-question-item">
              ${questionHead}
              <div class="questionnaire-blank-row">
                <span class="questionnaire-blank-type">填写约束：${escapeHtml(questionnaireConstraintLabel(q.constraint || "any"))}${hint}</span>
                <button type="button" class="questionnaire-add-btn" data-q-action="setting" data-q-id="${q.id}">
                  <i class="fa-solid fa-gear"></i><span>设置</span>
                </button>
              </div>
            </article>
          `;
        }
        const options = Array.isArray(q.options) ? q.options : [];
        return `
          <article class="questionnaire-question-item">
            ${questionHead}
            <div class="questionnaire-field">
              <span>选项</span>
              ${(options.length ? options : [""]).map((opt, optIdx) => `
                <div class="questionnaire-option-row">
                  <input type="text" data-q-action="option" data-q-id="${q.id}" data-opt-index="${optIdx}" value="${escapeHtml(opt || "")}" placeholder="请输入选项">
                  <button type="button" class="questionnaire-option-remove" data-q-action="remove-option" data-q-id="${q.id}" data-opt-index="${optIdx}">
                    <i class="fa-solid fa-minus"></i>
                  </button>
                </div>
              `).join("")}
            </div>
            <button type="button" class="questionnaire-add-btn" data-q-action="add-option" data-q-id="${q.id}">
              <i class="fa-solid fa-plus"></i><span>添加选项</span>
            </button>
          </article>
        `;
      })
      .join("");
    const addRowHtml = `
      <article class="questionnaire-question-add-item">
        <div class="questionnaire-add-row">
          <button type="button" class="questionnaire-add-btn" data-q-list-action="add-choice">
            <i class="fa-solid fa-plus"></i><span>添加选择题</span>
          </button>
          <button type="button" class="questionnaire-add-btn" data-q-list-action="add-blank">
            <i class="fa-solid fa-plus"></i><span>添加填空题</span>
          </button>
        </div>
      </article>
    `;
    if (!draft.questions.length) {
      list.innerHTML = `<div class="questionnaire-history-empty">请点击下方添加题目</div>${addRowHtml}`;
      return;
    }
    list.innerHTML = `${questionHtml}${addRowHtml}`;
  }

  function renderOverviewList(listId, rows, emptyText) {
    const host = el(listId);
    if (!host) {
      return;
    }
    host.innerHTML = "";

    if (!Array.isArray(rows) || rows.length === 0) {
      const empty = document.createElement("li");
      empty.className = "overview-list-empty";
      empty.textContent = emptyText;
      host.appendChild(empty);
      return;
    }

    rows.forEach((row) => {
      const li = document.createElement("li");
      li.className = "overview-list-item";

      const title = document.createElement("div");
      title.className = "row-title";
      title.textContent = row.title || "-";

      const meta = document.createElement("div");
      meta.className = "row-meta";
      meta.textContent = row.meta || "";

      li.appendChild(title);
      if (row.meta) {
        li.appendChild(meta);
      }

      if (row.tag) {
        const tag = document.createElement("span");
        tag.className = "row-tag";
        tag.textContent = row.tag;
        li.appendChild(tag);
      }

      host.appendChild(li);
    });
  }

  function renderLogsList() {
    const host = el("logs-list");
    if (!host) {
      return;
    }
    const rows = Array.isArray(state.logs.items) ? state.logs.items : [];
    if (!rows.length) {
      host.innerHTML = '<div class="questionnaire-history-empty">暂无日志</div>';
      return;
    }
    host.innerHTML = rows
      .map((row) => {
        const tags = [];
        if (row.spine_class_text) {
          const conf = row.confidence !== null && row.confidence !== undefined ? ` ${(Number(row.confidence) * 100).toFixed(1)}%` : "";
          tags.push(`<span class="log-tag">推理: ${escapeHtml(row.spine_class_text)}${escapeHtml(conf)}</span>`);
        }
        if (row.owner_name) {
          tags.push(`<span class="log-tag">负责医生: ${escapeHtml(row.owner_name)}</span>`);
        }
        const picChip =
          row.preview_url && row.pic_name
            ? `<span class="log-pic-chip">${escapeHtml(row.pic_name)}<span class="log-pic-tooltip"><img src="${escapeHtml(row.preview_url)}" alt="概述图"></span></span>`
            : "";
        return `
          <article class="log-item">
            <div class="log-item-head">
              <div class="log-title">${escapeHtml(row.title || "系统日志")}</div>
              <div class="log-time">${escapeHtml(formatShortDateTime(row.created_at))}</div>
            </div>
            <div class="log-message">${escapeHtml(row.message || "-")}</div>
            <div class="log-meta-row">
              ${picChip}
              ${tags.join("")}
            </div>
          </article>
        `;
      })
      .join("");
  }

  async function loadLogs(force = false) {
    if (state.logs.loading) {
      return;
    }
    if (!force && state.logs.loaded) {
      renderLogsList();
      return;
    }
    state.logs.loading = true;
    try {
      const data = await api("/api/logs");
      state.logs.items = Array.isArray(data.items) ? data.items : [];
      state.logs.loaded = true;
      renderLogsList();
    } catch (err) {
      state.logs.items = [];
      renderLogsList();
      showToast(err.message || "加载日志失败", "error");
    } finally {
      state.logs.loading = false;
    }
  }

  function getFilteredSortedPatients() {
    const keyword = (state.patients.search || "").trim().toLowerCase();
    const sorted = [...state.patients.list];
    const byText = (item) => [item.name, item.phone, item.email].join(" ").toLowerCase();

    let filtered = sorted;
    if (keyword) {
      filtered = sorted.filter((item) => byText(item).includes(keyword));
    }

    const sortKey = state.patients.sortKey || "updated_at";
    const sortDir = state.patients.sortDir === "asc" ? "asc" : "desc";
    const factor = sortDir === "asc" ? 1 : -1;

    const str = (value) => String(value || "");
    const date = (value) => new Date(value || 0).getTime() || 0;
    const num = (value) => {
      const n = Number(value);
      return Number.isFinite(n) ? n : -1;
    };

    filtered.sort((a, b) => {
      if (sortKey === "name") {
        return factor * str(a.name).localeCompare(str(b.name), "zh-CN");
      }
      if (sortKey === "age") {
        return factor * (num(a.age) - num(b.age));
      }
      if (sortKey === "sex") {
        return factor * str(a.sex).localeCompare(str(b.sex), "zh-CN");
      }
      if (sortKey === "last_followup") {
        return factor * (date(a.last_followup) - date(b.last_followup));
      }
      return factor * (date(a.updated_at) - date(b.updated_at));
    });
    return filtered;
  }

  function currentSortIcon(sortKey) {
    if (state.patients.sortKey !== sortKey) {
      return "fa-solid fa-sort";
    }
    return state.patients.sortDir === "asc" ? "fa-solid fa-sort-up" : "fa-solid fa-sort-down";
  }

  function updateSort(sortKey) {
    if (!sortKey) {
      return;
    }
    if (state.patients.sortKey === sortKey) {
      state.patients.sortDir = state.patients.sortDir === "asc" ? "desc" : "asc";
    } else {
      state.patients.sortKey = sortKey;
      state.patients.sortDir = sortKey === "name" ? "asc" : "desc";
    }
    renderPatientsList();
  }

  function renderPatientsList() {
    const host = el("patients-list");
    if (!host) {
      return;
    }
    host.innerHTML = "";
    const rows = getFilteredSortedPatients();
    if (!rows.length) {
      const empty = document.createElement("div");
      empty.className = "patients-empty";
      empty.textContent = state.patients.list.length ? "没有匹配的患者" : "暂无患者，点击右上角 + 添加";
      host.appendChild(empty);
      return;
    }

    const wrap = document.createElement("div");
    wrap.className = "patients-table-wrap";
    const table = document.createElement("table");
    table.className = "patients-table";
    table.innerHTML = `
      <thead>
        <tr>
          <th><button type="button" class="patients-sort-btn ${state.patients.sortKey === "name" ? `active ${state.patients.sortDir}` : ""}" data-sort-key="name">姓名 <i class="${currentSortIcon("name")}"></i></button></th>
          <th><button type="button" class="patients-sort-btn ${state.patients.sortKey === "age" ? `active ${state.patients.sortDir}` : ""}" data-sort-key="age">年龄 <i class="${currentSortIcon("age")}"></i></button></th>
          <th><button type="button" class="patients-sort-btn ${state.patients.sortKey === "sex" ? `active ${state.patients.sortDir}` : ""}" data-sort-key="sex">性别 <i class="${currentSortIcon("sex")}"></i></button></th>
          <th>电话</th>
          <th><button type="button" class="patients-sort-btn ${state.patients.sortKey === "last_followup" ? `active ${state.patients.sortDir}` : ""}" data-sort-key="last_followup">最后随访日期 <i class="${currentSortIcon("last_followup")}"></i></button></th>
          <th><button type="button" class="patients-sort-btn ${state.patients.sortKey === "updated_at" ? `active ${state.patients.sortDir}` : ""}" data-sort-key="updated_at">更新时间 <i class="${currentSortIcon("updated_at")}"></i></button></th>
          <th>状态</th>
          <th>操作</th>
        </tr>
      </thead>
      <tbody></tbody>
    `;

    const tbody = table.querySelector("tbody");
    rows.forEach((item) => {
      const tr = document.createElement("tr");
      tr.className = "patient-row";
      tr.dataset.patientId = String(item.id);
      tr.innerHTML = `
        <td class="patient-col-name">${escapeHtml(item.name || "-")}</td>
        <td>${escapeHtml(item.age ?? "-")}</td>
        <td>${escapeHtml(item.sex || "-")}</td>
        <td>${escapeHtml(item.phone || "-")}</td>
        <td>${formatDateOnly(item.last_followup)}</td>
        <td>${formatShortDateTime(item.updated_at)}</td>
        <td class="patient-col-status">${escapeHtml(item.status_text || "-")}</td>
        <td class="patient-actions">
          <button class="patient-delete" type="button" title="删除患者" data-action="delete">
            <i class="fa-solid fa-trash-can"></i>
          </button>
        </td>
      `;
      tbody?.appendChild(tr);
    });

    wrap.appendChild(table);
    host.appendChild(wrap);
  }

  function setRegisterStatus(text) {
    const node = el("register-session-status");
    if (node) {
      node.textContent = text || "";
    }
  }

  function setRegisterFocus(fieldName) {
    state.patients.register.focusField = fieldName || "";
    const hint = el("register-focus-hint");
    if (hint) {
      hint.textContent = fieldName ? `当前焦点：${fieldName}` : "当前焦点：无";
    }
    document.querySelectorAll("#register-form [data-reg-field]").forEach((input) => {
      const same = input.getAttribute("data-reg-field") === fieldName;
      input.classList.toggle("active-focus", !!same);
    });
  }

  function readRegisterFormState() {
    const stateObj = {};
    document.querySelectorAll("#register-form [data-reg-field]").forEach((input) => {
      const key = input.getAttribute("data-reg-field");
      if (!key) {
        return;
      }
      stateObj[key] = input.value;
    });
    return stateObj;
  }

  function applyRegisterFormState(nextState) {
    const data = nextState && typeof nextState === "object" ? nextState : {};
    state.patients.register.formState = { ...state.patients.register.formState, ...data };
    state.patients.register.applyingRemote = true;
    document.querySelectorAll("#register-form [data-reg-field]").forEach((input) => {
      const key = input.getAttribute("data-reg-field");
      if (!key) {
        return;
      }
      const nextValue = data[key];
      if (nextValue !== undefined && input.value !== String(nextValue ?? "")) {
        input.value = String(nextValue ?? "");
      }
    });
    state.patients.register.applyingRemote = false;
  }

  function resetRegisterState() {
    Object.values(state.patients.register.fieldTimers || {}).forEach((timerId) => window.clearTimeout(timerId));
    state.patients.register = {
      active: false,
      token: "",
      channel: "",
      formState: {},
      focusField: "",
      status: "",
      ws: null,
      wsReady: false,
      wsShouldReconnect: false,
      applyingRemote: false,
      fieldTimers: {},
    };
    setRegisterFocus("");
    setRegisterStatus("");
    const qr = el("register-qr-image");
    const link = el("register-link-input");
    if (qr) {
      qr.removeAttribute("src");
    }
    if (link) {
      link.value = "";
    }
    document.querySelectorAll("#register-form [data-reg-field]").forEach((input) => {
      input.value = "";
    });
  }

  function closeRegisterWs() {
    const reg = state.patients.register;
    reg.wsShouldReconnect = false;
    reg.wsReady = false;
    if (reg.ws && reg.ws.readyState === WebSocket.OPEN && reg.channel) {
      reg.ws.send(JSON.stringify({ type: "unsubscribe", channel: reg.channel }));
    }
    if (reg.ws) {
      try {
        reg.ws.close();
      } catch (_err) {
        // ignore
      }
    }
    reg.ws = null;
  }

  function handleRegisterWsMessage(msg) {
    const reg = state.patients.register;
    if (!reg.active) {
      return;
    }
    if (!msg || typeof msg !== "object") {
      return;
    }

    if (msg.type === "field_focus") {
      setRegisterFocus((msg.field || "").trim());
      return;
    }

    if (msg.type === "field_change") {
      const field = (msg.field || "").trim();
      if (!field) {
        return;
      }
      const patch = {};
      patch[field] = msg.value ?? "";
      applyRegisterFormState(patch);
      return;
    }

    if (msg.type === "form_submit") {
      const fullState = msg.form_state && typeof msg.form_state === "object" ? msg.form_state : {};
      applyRegisterFormState(fullState);
      const pname = (msg.patient && msg.patient.name) || fullState.name || "患者";
      showToast(`${pname} 已登记`, "success", { position: "bottom-right" });
      closePatientRegisterLayer(true);
    }
  }

  function ensureRegisterWs() {
    const reg = state.patients.register;
    if (!reg.active || !reg.channel) {
      return;
    }
    if (reg.ws && (reg.ws.readyState === WebSocket.OPEN || reg.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    reg.wsShouldReconnect = true;
    const ws = new WebSocket(getWsUrl());
    reg.ws = ws;

    ws.addEventListener("open", () => {
      reg.wsReady = true;
      ws.send(
        JSON.stringify({
          type: "hello",
          kind: "doctor",
          name: userDisplayName(state.user),
          id: state.user ? state.user.id : null,
        })
      );
      ws.send(JSON.stringify({ type: "subscribe", channel: reg.channel }));
      setRegisterStatus("会话已连接，等待患者填写...");
    });

    ws.addEventListener("message", (event) => {
      try {
        const msg = JSON.parse(event.data || "{}");
        handleRegisterWsMessage(msg);
      } catch (_err) {
        // ignore parse error
      }
    });

    ws.addEventListener("close", () => {
      reg.wsReady = false;
      reg.ws = null;
      if (reg.active && reg.wsShouldReconnect) {
        window.setTimeout(ensureRegisterWs, 1200);
      }
    });

    ws.addEventListener("error", () => {
      setRegisterStatus("实时通道异常，正在重连...");
    });
  }

  async function syncRegisterFocus(field) {
    const reg = state.patients.register;
    if (!reg.active || !reg.token) {
      return;
    }
    try {
      await api(`/api/registration-sessions/${reg.token}/focus`, {
        method: "POST",
        body: {
          field,
          actor_name: userDisplayName(state.user),
        },
      });
    } catch (_err) {
      // ignore
    }
  }

  function syncRegisterFieldDebounced(field, value) {
    const reg = state.patients.register;
    if (!reg.active || !reg.token) {
      return;
    }
    if (reg.applyingRemote) {
      return;
    }
    if (reg.fieldTimers[field]) {
      window.clearTimeout(reg.fieldTimers[field]);
    }
    reg.fieldTimers[field] = window.setTimeout(async () => {
      try {
        await api(`/api/registration-sessions/${reg.token}/field`, {
          method: "POST",
          body: {
            field,
            value,
            actor_name: userDisplayName(state.user),
          },
        });
        reg.formState[field] = value;
      } catch (_err) {
        // ignore
      }
    }, 180);
  }

  async function loadRegisterSession(token) {
    if (!token) {
      return;
    }
    const data = await api(`/api/registration-sessions/${token}`);
    const formState = data.form_state && typeof data.form_state === "object" ? data.form_state : {};
    applyRegisterFormState(formState);
    setRegisterFocus((data.focus_field || "").trim());
    setRegisterStatus(data.status === "submitted" ? "已提交登记" : "等待患者填写...");
  }

  function openPatientRegisterLayer() {
    const layer = el("patients-register-layer");
    const panel = el("patients-panel");
    if (!layer) {
      return;
    }
    closePatientDetailLayer();
    layer.classList.remove("hidden");
    panel?.classList.add("patients-register-mode");
  }

  function closePatientRegisterLayer(refreshList = false) {
    const layer = el("patients-register-layer");
    const panel = el("patients-panel");
    if (layer) {
      layer.classList.add("hidden");
    }
    panel?.classList.remove("patients-register-mode");
    closeRegisterWs();
    resetRegisterState();
    if (refreshList) {
      loadPatients(true);
    }
  }

  async function startPatientRegistration() {
    try {
      setRegisterStatus("正在创建登记会话...");
      openPatientRegisterLayer();
      const data = await api("/api/registration-sessions", { method: "POST", body: {} });
      const reg = state.patients.register;
      reg.active = true;
      reg.token = data.token || "";
      reg.channel = data.channel || "";
      reg.formState = data.form_state && typeof data.form_state === "object" ? data.form_state : {};
      const qr = el("register-qr-image");
      const link = el("register-link-input");
      if (qr) {
        qr.src = data.qr_data_url || "";
      }
      if (link) {
        link.value = data.register_url || "";
      }
      applyRegisterFormState(reg.formState);
      setRegisterStatus("会话已创建，等待患者填写...");
      ensureRegisterWs();
      await loadRegisterSession(reg.token);
    } catch (err) {
      closePatientRegisterLayer(false);
      showToast(err.message || "创建登记会话失败", "error");
    }
  }

  async function submitPatientRegistrationFromDoctor() {
    const reg = state.patients.register;
    if (!reg.active || !reg.token) {
      showToast("登记会话未就绪", "warn");
      return;
    }
    const formState = readRegisterFormState();
    if (!(formState.name || "").trim()) {
      showToast("姓名必填", "warn");
      return;
    }
    try {
      const data = await api(`/api/registration-sessions/${reg.token}/submit`, {
        method: "POST",
        body: {
          actor_name: userDisplayName(state.user),
          form_state: formState,
        },
      });
      const pname = (data.patient && data.patient.name) || formState.name || "患者";
      showToast(`${pname} 已登记`, "success", { position: "bottom-right" });
      closePatientRegisterLayer(true);
    } catch (err) {
      showToast(err.message || "登记提交失败", "error");
    }
  }

  function openPatientDetailLayer() {
    const layer = el("patients-detail-layer");
    const panel = el("patients-panel");
    if (!layer) {
      return;
    }
    layer.classList.remove("hidden");
    panel?.classList.add("patients-detail-mode");
    state.patients.detailTab = state.patients.detailTab || "basic";
    state.patients.detailEditing = false;
    closePatientRegisterLayer(false);
  }

  function closePatientDetailLayer() {
    const layer = el("patients-detail-layer");
    const panel = el("patients-panel");
    if (!layer) {
      return;
    }
    layer.classList.add("hidden");
    panel?.classList.remove("patients-detail-mode");
  }

  function patientRiskLevelText(level) {
    const key = String(level || "low");
    if (key === "high") {
      return "高风险";
    }
    if (key === "medium") {
      return "中风险";
    }
    return "低风险";
  }

  function patientRiskLevelClass(level) {
    const key = String(level || "low");
    if (key === "high") {
      return "risk-high";
    }
    if (key === "medium") {
      return "risk-medium";
    }
    return "risk-low";
  }

  function renderPatientTrendChart(trendRows) {
    const rows = (Array.isArray(trendRows) ? trendRows : [])
      .filter((row) => Number.isFinite(Number(row?.cobb_angle)))
      .slice(-12);
    if (rows.length < 2) {
      return '<div class="patient-status-trend-empty">趋势数据不足，至少需要 2 次有效影像记录。</div>';
    }

    const values = rows.map((row) => Number(row.cobb_angle));
    const minValue = Math.min(...values);
    const maxValue = Math.max(...values);
    const span = Math.max(1, maxValue - minValue);

    const width = 480;
    const height = 180;
    const padX = 30;
    const padY = 24;

    const points = rows.map((row, idx) => {
      const ratioX = rows.length <= 1 ? 0 : idx / (rows.length - 1);
      const x = padX + ratioX * (width - padX * 2);
      const y = height - padY - ((Number(row.cobb_angle) - minValue) / span) * (height - padY * 2);
      return {
        x,
        y,
        value: Number(row.cobb_angle),
        date: row.date,
      };
    });

    const polylinePoints = points.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(" ");
    const minLabel = `${minValue.toFixed(1)}°`;
    const maxLabel = `${maxValue.toFixed(1)}°`;
    const startLabel = formatDateOnly(rows[0].date);
    const endLabel = formatDateOnly(rows[rows.length - 1].date);

    return `
      <div class="patient-status-trend-chart-wrap">
        <svg class="patient-status-trend-chart" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" role="img" aria-label="Cobb 角趋势图">
          <line x1="${padX}" y1="${height - padY}" x2="${width - padX}" y2="${height - padY}" stroke="#cbd5e1" stroke-width="1"></line>
          <line x1="${padX}" y1="${padY}" x2="${padX}" y2="${height - padY}" stroke="#cbd5e1" stroke-width="1"></line>
          <polyline fill="none" stroke="#2563eb" stroke-width="3" points="${polylinePoints}"></polyline>
          ${points
            .map(
              (p) =>
                `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="4" fill="#1d4ed8"><title>${escapeHtml(
                  `${formatDateOnly(p.date)} · ${p.value.toFixed(1)}°`
                )}</title></circle>`
            )
            .join("")}
          <text x="${padX}" y="${padY - 6}" fill="#475569" font-size="11">${escapeHtml(maxLabel)}</text>
          <text x="${padX}" y="${height - padY + 16}" fill="#475569" font-size="11">${escapeHtml(minLabel)}</text>
        </svg>
        <div class="patient-status-trend-axis">
          <span>${escapeHtml(startLabel)}</span>
          <span>${escapeHtml(endLabel)}</span>
        </div>
      </div>
    `;
  }

  function pickUploadClassificationChoice() {
    const modal = el("upload-classify-modal");
    const closeBtn = el("upload-classify-close-btn");
    const cancelBtn = el("upload-classify-cancel-btn");
    const confirmBtn = el("upload-classify-confirm-btn");
    const manualGroup = el("upload-manual-class-group");
    const manualSelect = el("upload-manual-class-select");
    const modeInputs = Array.from(modal?.querySelectorAll("input[name='upload-classify-mode']") || []);

    if (!modal || !modeInputs.length || !confirmBtn) {
      return Promise.resolve({ classificationMode: "ai", manualSpineClass: "" });
    }

    const readMode = () => {
      const checked = modeInputs.find((node) => node.checked);
      const mode = String(checked?.value || "ai").toLowerCase();
      return mode === "manual" ? "manual" : "ai";
    };

    return new Promise((resolve) => {
      const syncManualGroup = () => {
        const isManual = readMode() === "manual";
        manualGroup?.classList.toggle("hidden", !isManual);
      };

      const cleanup = () => {
        modeInputs.forEach((node) => node.removeEventListener("change", syncManualGroup));
        closeBtn?.removeEventListener("click", onCancel);
        cancelBtn?.removeEventListener("click", onCancel);
        confirmBtn.removeEventListener("click", onConfirm);
        modal.removeEventListener("click", onBackdropClick);
        modal.classList.add("hidden");
        modal.setAttribute("aria-hidden", "true");
      };

      const onCancel = () => {
        cleanup();
        resolve(null);
      };

      const onConfirm = () => {
        const classificationMode = readMode();
        const manualSpineClass = String(manualSelect?.value || "").trim();
        if (classificationMode === "manual" && !manualSpineClass) {
          showToast("请选择手动分类类型", "warn");
          manualSelect?.focus();
          return;
        }
        cleanup();
        resolve({
          classificationMode,
          manualSpineClass: classificationMode === "manual" ? manualSpineClass : "",
        });
      };

      const onBackdropClick = (event) => {
        if (event.target === modal) {
          onCancel();
        }
      };

      modeInputs.forEach((node) => {
        node.checked = String(node.value || "").toLowerCase() === "ai";
        node.addEventListener("change", syncManualGroup);
      });
      if (manualSelect) {
        manualSelect.value = "";
      }

      closeBtn?.addEventListener("click", onCancel);
      cancelBtn?.addEventListener("click", onCancel);
      confirmBtn.addEventListener("click", onConfirm);
      modal.addEventListener("click", onBackdropClick);

      syncManualGroup();
      modal.classList.remove("hidden");
      modal.setAttribute("aria-hidden", "false");
    });
  }

  async function startPatientExamUpload(patientId) {
    const id = Number(patientId);
    if (!Number.isFinite(id)) {
      showToast("患者信息无效，无法上传", "warn");
      return;
    }

    const picker = document.createElement("input");
    picker.type = "file";
    picker.accept = "image/*";

    picker.addEventListener("change", async () => {
      const file = picker.files && picker.files[0] ? picker.files[0] : null;
      if (!file) {
        return;
      }

      const classifyChoice = await pickUploadClassificationChoice();
      if (!classifyChoice) {
        return;
      }

      const formData = new FormData();
      formData.append("file", file);
      formData.append("classification_mode", classifyChoice.classificationMode);
      if (classifyChoice.classificationMode === "manual" && classifyChoice.manualSpineClass) {
        formData.append("manual_spine_class", classifyChoice.manualSpineClass);
      }

      try {
        showToast("影像上传中...", "info");
        await apiMultipart(`/api/patients/${id}/exams`, formData);
        const refreshed = await api(`/api/patients/${id}`);
        state.patients.detailMap[id] = refreshed;
        renderPatientDetail(refreshed);
        await loadPatients(true);
        showToast("影像上传成功，AI 正在分析", "success");
      } catch (err) {
        showToast(err.message || "影像上传失败", "error");
      }
    });

    picker.click();
  }

  function renderPatientDetail(detail) {
    const host = el("patients-detail-content");
    if (!host) {
      return;
    }
    if (!detail || !detail.patient) {
      host.innerHTML = `<div class="patients-empty">未找到患者详情</div>`;
      return;
    }

    const p = detail.patient;
    const exams = Array.isArray(p.exams) ? p.exams : [];
    const timeline = Array.isArray(p.timeline) ? p.timeline : [];
    const isEditing = state.patients.detailEditing && Number(state.patients.detailId) === Number(p.id);
    const safeName = escapeHtml(p.name || "-");
    const safeNote = escapeHtml(p.note || "");
    const portalUrl = String(p.portal_url || "");
    const safePortalUrl = escapeHtml(portalUrl);
    const tab = state.patients.detailTab === "status" ? "status" : "basic";
    const basicTabBtn = el("patients-tab-basic");
    const statusTabBtn = el("patients-tab-status");
    basicTabBtn?.classList.toggle("active", tab === "basic");
    statusTabBtn?.classList.toggle("active", tab === "status");
    const sexOptions = ["男", "女", "其他", "未知"];
    const sexValue = String(p.sex || "");
    const sexHtml = sexOptions
      .map((v) => `<option value="${escapeHtml(v)}" ${sexValue === v ? "selected" : ""}>${escapeHtml(v)}</option>`)
      .join("");

    const followup = p.followup && typeof p.followup === "object" ? p.followup : {};
    const riskScoreRaw = Number(followup.risk_score);
    const riskScore = Number.isFinite(riskScoreRaw) ? Math.max(0, Math.min(100, Math.round(riskScoreRaw))) : null;
    const riskScorePercent = Number.isFinite(riskScore) ? riskScore : 0;
    const riskLevel = String(followup.risk_level || "low");
    const riskLevelText = patientRiskLevelText(riskLevel);
    const riskLevelClass = patientRiskLevelClass(riskLevel);
    const treatmentPhase = followup.treatment_phase && typeof followup.treatment_phase === "object" ? followup.treatment_phase : {};
    const treatmentPhaseLabel = String(treatmentPhase.label || "常规随访期");
    const treatmentPhaseDesc = String(treatmentPhase.description || "暂无治疗阶段说明");
    const completionRate = Number(followup.completion_rate);
    const completionText = Number.isFinite(completionRate) ? `${completionRate.toFixed(1)}%` : "-";
    const nextDueText = followup.next_due_at ? formatShortDateTime(followup.next_due_at) : "--";
    const activeSchedules = Number(followup.active_schedules);
    const totalSchedules = Number(followup.total_schedules);
    const overdueSchedules = Number(followup.overdue_schedules);
    const dueSoonSchedules = Number(followup.due_soon_schedules);
    const followupSummary = String(followup.summary || "暂无随访总结");
    const riskTags = Array.isArray(followup.risk_tags) ? followup.risk_tags : [];
    const trendRows = Array.isArray(followup.trend) ? followup.trend : Array.isArray(p.trend) ? p.trend : [];
    const trendChartHtml = renderPatientTrendChart(trendRows);

    host.innerHTML = tab === "status"
      ? `
      <div class="patient-detail-layout">
        <section class="patient-detail-card patient-detail-card-main">
          <header class="patient-detail-main-head">
            <h3>${safeName} 的状况</h3>
            <span class="patient-status-level-chip ${riskLevelClass}">${riskLevelText}</span>
          </header>

          <div class="patient-status-kpi-grid">
            <article class="patient-status-kpi ${riskLevelClass}">
              <span>风险评分</span>
              <strong>${riskScore !== null ? String(riskScore) : "-"}</strong>
              <p>${riskLevelText}</p>
              <div class="patient-status-risk-bar"><span style="width:${riskScorePercent}%"></span></div>
            </article>
            <article class="patient-status-kpi">
              <span>治疗阶段</span>
              <strong>${escapeHtml(treatmentPhaseLabel)}</strong>
              <p>${escapeHtml(treatmentPhaseDesc)}</p>
            </article>
            <article class="patient-status-kpi">
              <span>下次随访</span>
              <strong>${escapeHtml(nextDueText)}</strong>
              <p>逾期 ${Number.isFinite(overdueSchedules) ? overdueSchedules : 0} · 即将到期 ${Number.isFinite(dueSoonSchedules) ? dueSoonSchedules : 0}</p>
            </article>
            <article class="patient-status-kpi">
              <span>随访完成率</span>
              <strong>${escapeHtml(completionText)}</strong>
              <p>进行中 ${Number.isFinite(activeSchedules) ? activeSchedules : 0} · 总计划 ${Number.isFinite(totalSchedules) ? totalSchedules : 0}</p>
            </article>
          </div>

          <section class="patient-status-section">
            <h4>Cobb 趋势图</h4>
            <div class="patient-status-trend">${trendChartHtml}</div>
          </section>

          <section class="patient-status-section">
            <h4>风险标签</h4>
            <div class="patient-status-tags">
              ${
                riskTags.length
                  ? riskTags.map((tag) => `<span class="patient-status-tag ${riskLevelClass}">${escapeHtml(tag)}</span>`).join("")
                  : '<span class="patient-status-tag">暂无风险标签</span>'
              }
            </div>
            <p class="patient-status-summary">${escapeHtml(followupSummary)}</p>
          </section>
        </section>
        <div class="patient-detail-side">
          <section class="patient-detail-card">
            <div class="patient-detail-card-head">
              <h3>影像记录（${exams.length}）</h3>
              <button type="button" class="patient-detail-btn" data-patient-upload-btn>
                <i class="fa-solid fa-file-circle-plus"></i><span>上传影像</span>
              </button>
            </div>
            <ul class="patient-detail-list">
              ${
                exams.length
                  ? exams
                      .slice(0, 20)
                      .map(
                        (e) => {
                          const kind = String(e.spine_class || "").toLowerCase();
                          const metric =
                            kind === "cervical"
                              ? `左/右比 ${formatRatio(e.cervical_avg_ratio, 3)}`
                              : `Cobb ${formatOneDecimal(e.cobb_angle, "°")}`;
                          return `<li>${formatShortDateTime(e.upload_date)} · ${metric} · ${e.status || "-"}</li>`;
                        }
                      )
                      .join("")
                  : `<li>暂无影像记录</li>`
              }
            </ul>
          </section>
          <section class="patient-detail-card patient-detail-card-timeline">
            <h3>时间线（${timeline.length}）</h3>
            <ul class="patient-detail-list patient-detail-list-scroll">
              ${
                timeline.length
                  ? timeline
                      .slice(0, 30)
                      .map(
                        (e) => `<li>${formatTimelineDateTime(e.created_at)} · ${e.title || "-"} · ${e.message || "-"}</li>`
                      )
                      .join("")
                  : `<li>暂无时间线记录</li>`
              }
            </ul>
          </section>
        </div>
      </div>
    `
      : `
      <div class="patient-detail-layout">
        <section class="patient-detail-card patient-detail-card-main">
          <header class="patient-detail-main-head">
            <h3>${safeName} 的基本信息</h3>
            <div class="patient-detail-head-actions">
              ${
                isEditing
                  ? `
                    <button id="patient-detail-save-btn" type="button" class="patient-detail-btn save">
                      <i class="fa-solid fa-floppy-disk"></i><span>保存</span>
                    </button>
                    <button id="patient-detail-cancel-btn" type="button" class="patient-detail-btn">
                      <span>取消</span>
                    </button>
                  `
                  : `
                    <button id="patient-detail-edit-btn" type="button" class="patient-detail-icon-btn" title="编辑基本信息">
                      <i class="fa-solid fa-gear"></i>
                    </button>
                  `
              }
            </div>
          </header>

          <div class="patient-detail-dense-table-wrap ${isEditing ? "editing" : ""}">
            <table class="patient-detail-dense-table" role="table" aria-label="患者基础信息表">
              <tbody>
                <tr>
                  <th scope="row">姓名</th>
                  <td>
                    ${isEditing ? `<input id="patient-field-name" type="text" value="${escapeHtml(p.name || "")}">` : `<strong>${escapeHtml(p.name || "-")}</strong>`}
                  </td>
                  <th scope="row">性别</th>
                  <td>
                    ${isEditing ? `<select id="patient-field-sex"><option value="">未设置</option>${sexHtml}</select>` : `<strong>${escapeHtml(p.sex || "-")}</strong>`}
                  </td>
                </tr>
                <tr>
                  <th scope="row">年龄</th>
                  <td>
                    ${isEditing ? `<input id="patient-field-age" type="number" min="0" max="130" value="${escapeHtml(p.age ?? "")}">` : `<strong>${escapeHtml(p.age ?? "-")}</strong>`}
                  </td>
                  <th scope="row">电话</th>
                  <td>
                    ${isEditing ? `<input id="patient-field-phone" type="text" value="${escapeHtml(p.phone || "")}">` : `<strong>${escapeHtml(p.phone || "-")}</strong>`}
                  </td>
                </tr>
                <tr>
                  <th scope="row">邮箱</th>
                  <td colspan="3">
                    ${isEditing ? `<input id="patient-field-email" type="text" value="${escapeHtml(p.email || "")}">` : `<strong>${escapeHtml(p.email || "-")}</strong>`}
                  </td>
                </tr>
                <tr>
                  <th scope="row">备注</th>
                  <td colspan="3">
                    ${isEditing ? `<textarea id="patient-field-note" rows="2">${safeNote}</textarea>` : `<strong class="patient-detail-note-text">${safeNote || "-"}</strong>`}
                  </td>
                </tr>
                <tr>
                  <th scope="row">状态</th>
                  <td><strong>${escapeHtml(p.status_text || "-")}</strong></td>
                  <th scope="row">随访周期(天)</th>
                  <td>
                    ${isEditing ? `<input id="patient-field-followup-cycle-days" type="number" min="1" max="365" step="1" inputmode="numeric" value="${escapeHtml(p.followup_cycle_days ?? "")}">` : `<strong>${escapeHtml(p.followup_cycle_days ?? "-")}</strong>`}
                  </td>
                </tr>
                <tr>
                  <th scope="row">专属随访门户URL</th>
                  <td colspan="3">
                    <div class="patient-detail-url-inline">
                      <span class="patient-detail-url-text">${safePortalUrl}</span>
                      <div class="patient-detail-url-actions">
                        <button id="patient-portal-copy-btn" type="button" title="复制链接"><i class="fa-solid fa-copy"></i></button>
                        <a id="patient-portal-open-btn" href="${safePortalUrl}" target="_blank" rel="noopener noreferrer" title="打开链接"><i class="fa-solid fa-up-right-from-square"></i></a>
                      </div>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <div class="patient-detail-side">
          <section class="patient-detail-card">
            <div class="patient-detail-card-head">
              <h3>影像记录（${exams.length}）</h3>
              <button type="button" class="patient-detail-btn" data-patient-upload-btn>
                <i class="fa-solid fa-file-circle-plus"></i><span>上传影像</span>
              </button>
            </div>
            <ul class="patient-detail-list">
              ${
                exams.length
                  ? exams
                      .slice(0, 20)
                      .map(
                        (e) => {
                          const kind = String(e.spine_class || "").toLowerCase();
                          const metric =
                            kind === "cervical"
                              ? `左/右比 ${formatRatio(e.cervical_avg_ratio, 3)}`
                              : `Cobb ${formatOneDecimal(e.cobb_angle, "°")}`;
                          return `<li>${formatShortDateTime(e.upload_date)} · ${metric} · ${e.status || "-"}</li>`;
                        }
                      )
                      .join("")
                  : `<li>暂无影像记录</li>`
              }
            </ul>
          </section>

          <section class="patient-detail-card patient-detail-card-timeline">
            <h3>时间线（${timeline.length}）</h3>
            <ul class="patient-detail-list patient-detail-list-scroll">
              ${
                timeline.length
                  ? timeline
                      .slice(0, 30)
                      .map(
                        (e) => `<li>${formatTimelineDateTime(e.created_at)} · ${e.title || "-"} · ${e.message || "-"}</li>`
                      )
                      .join("")
                  : `<li>暂无时间线记录</li>`
              }
            </ul>
          </section>
        </div>
      </div>
    `;

    const editBtn = el("patient-detail-edit-btn");
    const cancelBtn = el("patient-detail-cancel-btn");
    const saveBtn = el("patient-detail-save-btn");

    host.querySelectorAll("[data-patient-upload-btn]").forEach((btn) => {
      btn.addEventListener("click", () => {
        startPatientExamUpload(p.id);
      });
    });

    editBtn?.addEventListener("click", () => {
      state.patients.detailEditing = true;
      renderPatientDetail(detail);
    });
    cancelBtn?.addEventListener("click", () => {
      state.patients.detailEditing = false;
      renderPatientDetail(detail);
    });
    saveBtn?.addEventListener("click", async () => {
      const id = Number(p.id);
      if (!Number.isFinite(id)) {
        return;
      }
      const ageRaw = (el("patient-field-age")?.value || "").trim();
      const payload = {
        name: (el("patient-field-name")?.value || "").trim(),
        age: ageRaw === "" ? null : Number(ageRaw),
        sex: (el("patient-field-sex")?.value || "").trim(),
        phone: (el("patient-field-phone")?.value || "").trim(),
        email: (el("patient-field-email")?.value || "").trim(),
        note: (el("patient-field-note")?.value || "").trim(),
      };
      if (!payload.name) {
        showToast("姓名不能为空", "warn");
        return;
      }
      if (ageRaw !== "" && !Number.isFinite(payload.age)) {
        showToast("年龄格式不正确", "warn");
        return;
      }

      try {
        const data = await api(`/api/patients/${id}`, { method: "PATCH", body: payload });
        if (!data || !data.patient) {
          showToast("保存失败", "error");
          return;
        }

        state.patients.list = state.patients.list.map((i) => (i.id === id ? { ...i, ...data.patient } : i));

        const baseDetail = state.patients.detailMap[id] || detail;
        state.patients.detailMap[id] = {
          ...baseDetail,
          patient: {
            ...baseDetail.patient,
            ...data.patient,
            note: payload.note || null,
          },
        };
        state.patients.detailEditing = false;
        renderPatientsList();
        renderPatientDetail(state.patients.detailMap[id]);
        showToast("基本信息已保存", "success");
      } catch (err) {
        showToast(err.message || "保存失败", "error");
      }
    });

    const copyBtn = el("patient-portal-copy-btn");
    copyBtn?.addEventListener("click", async () => {
      const text = portalUrl.trim();
      if (!text) {
        showToast("暂无可复制链接", "warn");
        return;
      }
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
        } else {
          const input = el("patient-portal-url");
          input?.focus();
          input?.select();
          document.execCommand("copy");
        }
        showToast("链接已复制", "success");
      } catch (_err) {
        showToast("复制失败", "error");
      }
    });
  }

  async function loadPatientDetail(patientId) {
    const id = Number(patientId);
    if (!Number.isFinite(id)) {
      return;
    }

    const listLayer = el("patients-list-layer");
    if (listLayer) {
      state.patients.listScrollTop = listLayer.scrollTop || 0;
    }

    state.patients.detailId = id;
    state.patients.detailTab = "basic";
    openPatientDetailLayer();

    if (state.patients.detailMap[id]) {
      renderPatientDetail(state.patients.detailMap[id]);
      return;
    }

    try {
      const data = await api(`/api/patients/${id}`);
      state.patients.detailMap[id] = data;
      renderPatientDetail(data);
    } catch (err) {
      renderPatientDetail(null);
      showToast(err.message || "加载患者详情失败", "error");
    }
  }

  function backToPatientList() {
    closePatientDetailLayer();
    const listLayer = el("patients-list-layer");
    if (listLayer) {
      listLayer.scrollTop = state.patients.listScrollTop || 0;
    }
    state.patients.detailId = null;
    state.patients.detailTab = "basic";
    state.patients.detailEditing = false;
  }

  async function loadPatients(force = false) {
    if (state.patients.loading) {
      return;
    }
    if (state.patients.loaded && !force) {
      renderPatientsList();
      return;
    }
    state.patients.loading = true;
    try {
      const data = await api("/api/patients");
      state.patients.list = Array.isArray(data.items) ? data.items : [];
      state.patients.loaded = true;
      renderPatientsList();
    } catch (err) {
      showToast(err.message || "加载患者列表失败", "error");
    } finally {
      state.patients.loading = false;
    }
  }

  async function deletePatient(patientId) {
    const id = Number(patientId);
    if (!Number.isFinite(id)) {
      return;
    }
    const row = state.patients.list.find((i) => i.id === id);
    const name = row ? row.name : `#${id}`;
    const ok = window.confirm(`确认删除患者 ${name} 吗？`);
    if (!ok) {
      return;
    }
    try {
      await api(`/api/patients/${id}`, { method: "DELETE" });
      state.patients.list = state.patients.list.filter((i) => i.id !== id);
      delete state.patients.detailMap[id];
      renderPatientsList();
      if (state.patients.detailId === id) {
        backToPatientList();
      }
      showToast("患者已删除", "success");
    } catch (err) {
      showToast(err.message || "删除患者失败", "error");
    }
  }

  function renderOverviewLists(feedRows, scheduleRows, pendingReviews) {
    const followupRows = [];
    const taskRows = [];
    const schedules = Array.isArray(scheduleRows) ? scheduleRows : [];
    const feeds = Array.isArray(feedRows) ? feedRows : [];
    const pendingCount = Number.isFinite(Number(pendingReviews)) ? Number(pendingReviews) : 0;

    schedules.slice(0, 6).forEach((item) => {
      const status = String(item.status || "todo");
      const statusText = status === "overdue" ? "逾期" : "待办";
      followupRows.push({
        title: `${item.patient_name || "-"} · ${item.title || "未命名日程"}`,
        meta: `${statusText} · ${formatShortDateTime(item.scheduled_at)}`,
        tag: status === "overdue" ? "紧急" : "随访",
      });
    });

    if (pendingCount > 0) {
      taskRows.push({
        title: `待复核影像 ${pendingCount} 项`,
        meta: "请优先处理高风险影像",
        tag: "复核",
      });
    }

    feeds.slice(0, 6).forEach((item) => {
      taskRows.push({
        title: item.title || "系统事件",
        meta: `${item.message || ""} · ${formatShortDateTime(item.created_at)}`,
        tag: item.level === "warn" ? "提醒" : "动态",
      });
    });

    const followupDesc = el("overview-followup-card-desc");
    const followupBadge = el("overview-followup-card-badge");
    const taskDesc = el("overview-task-card-desc");
    const taskBadge = el("overview-task-card-badge");

    if (followupDesc) {
      followupDesc.textContent = followupRows.length ? `待跟进 ${followupRows.length} 条` : "暂无待跟进";
    }
    if (followupBadge) {
      const overdue = schedules.filter((i) => String(i.status || "") === "overdue").length;
      followupBadge.textContent = overdue > 0 ? `逾期 ${overdue}` : "正常";
    }
    if (taskDesc) {
      taskDesc.textContent = taskRows.length ? `待处理 ${taskRows.length} 条` : "暂无待处理";
    }
    if (taskBadge) {
      taskBadge.textContent = pendingCount > 0 ? `复核 ${pendingCount}` : "正常";
    }

    renderOverviewList("overview-followup-list", followupRows, "当前暂无随访提醒");
    renderOverviewList("overview-task-list", taskRows, "当前暂无任务提醒");

    // Backward compatibility with old shell IDs.
    renderOverviewList("overview-todo-list", followupRows, "当前暂无待办任务");
    renderOverviewList("overview-reminder-list", taskRows, "当前暂无提醒");
  }

  function numOrNull(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function formatMB(value) {
    if (!Number.isFinite(value)) {
      return "--";
    }
    if (value >= 1024) {
      return `${(value / 1024).toFixed(2)} GB`;
    }
    return `${value.toFixed(1)} MB`;
  }

  function renderPieChart(pieId, centerId, legendId, items, centerText) {
    const pieNode = el(pieId);
    const centerNode = el(centerId);
    const legendNode = el(legendId);
    if (!pieNode || !centerNode || !legendNode) {
      return;
    }

    const valid = (items || []).filter((i) => Number.isFinite(i.value) && i.value >= 0);
    const total = valid.reduce((sum, i) => sum + i.value, 0);

    if (total > 0) {
      let cursor = 0;
      const stops = [];
      valid.forEach((item) => {
        const start = (cursor / total) * 360;
        cursor += item.value;
        const end = (cursor / total) * 360;
        stops.push(`${item.color} ${start}deg ${end}deg`);
      });
      pieNode.style.background = `conic-gradient(${stops.join(", ")})`;
    } else {
      pieNode.style.background = "conic-gradient(#d1d5db 0 360deg)";
    }

    centerNode.textContent = centerText || "--";

    legendNode.innerHTML = "";
    if (!valid.length) {
      const li = document.createElement("li");
      li.innerHTML = `<span class="dot" style="background:#d1d5db"></span><span class="label">暂无数据</span>`;
      legendNode.appendChild(li);
      return;
    }

    valid.forEach((item) => {
      const li = document.createElement("li");
      const label = document.createElement("span");
      label.className = "label";
      label.textContent = `${item.label}：${item.display || item.value}`;

      const dot = document.createElement("span");
      dot.className = "dot";
      dot.style.background = item.color;

      li.appendChild(dot);
      li.appendChild(label);
      legendNode.appendChild(li);
    });
  }

  function renderStatusErrors(rows) {
    const host = el("status-error-list");
    if (!host) {
      return;
    }
    host.innerHTML = "";
    const items = Array.isArray(rows) ? rows : [];
    if (!items.length) {
      const li = document.createElement("li");
      li.className = "empty";
      li.textContent = "最近没有推理错误";
      host.appendChild(li);
      return;
    }

    items.forEach((item) => {
      const li = document.createElement("li");
      const examLabel = item.exam_id ? `Exam #${item.exam_id}` : "Exam";
      li.innerHTML = `<div>${examLabel} · ${formatShortDateTime(item.finished_at)}</div><div>${item.error || "未知错误"}</div>`;
      host.appendChild(li);
    });
  }

  function renderUsersPanel() {
    const listEl = el("users-list");
    const detailTitle = el("users-detail-title");
    const detailContent = el("users-detail-content");
    if (!listEl || !detailTitle || !detailContent) {
      return;
    }
    if (state.users.loading) {
      listEl.innerHTML = '<div class="questionnaire-history-empty">正在加载用户列表...</div>';
      detailTitle.textContent = "用户详细控制";
      detailContent.innerHTML = '<div class="questionnaire-history-empty">请稍候...</div>';
      return;
    }
    const rows = Array.isArray(state.users.list) ? state.users.list : [];
    if (!rows.length) {
      listEl.innerHTML = '<div class="questionnaire-history-empty">暂无用户数据</div>';
      detailTitle.textContent = "用户详细控制";
      detailContent.innerHTML = '<div class="questionnaire-history-empty">暂无可显示内容</div>';
      return;
    }
    if (!rows.some((u) => Number(u.id) === Number(state.users.selectedId || 0))) {
      state.users.selectedId = Number(rows[0].id) || null;
    }
    listEl.innerHTML = rows
      .map((row) => {
        const uid = Number(row.id) || 0;
        const active = uid === Number(state.users.selectedId || 0);
        const roleMap = { admin: "管理员", doctor: "医生", nurse: "护士" };
        const role = roleMap[String(row.role || "").toLowerCase()] || (row.role || "user");
        return `
          <article class="users-item ${active ? "active" : ""}" data-user-id="${uid}">
            <div class="users-item-name">${escapeHtml(row.display_name || row.username || `用户-${uid}`)}</div>
            <div class="users-item-meta">${escapeHtml(role)}</div>
          </article>
        `;
      })
      .join("");

    const current = rows.find((u) => Number(u.id) === Number(state.users.selectedId || 0)) || rows[0];
    const roleMap = { admin: "管理员", doctor: "医生", nurse: "护士" };
    const role = roleMap[String(current.role || "").toLowerCase()] || (current.role || "user");
    detailTitle.textContent = `${current.display_name || current.username || "用户"} · 详细控制`;
    detailContent.innerHTML = `
      <div class="users-detail-placeholder">
        <div class="users-detail-grid">
          <article class="users-detail-card"><div class="k">用户ID</div><div class="v">${Number(current.id) || "-"}</div></article>
          <article class="users-detail-card"><div class="k">用户名</div><div class="v">${escapeHtml(current.username || "-")}</div></article>
          <article class="users-detail-card"><div class="k">显示名</div><div class="v">${escapeHtml(current.display_name || "-")}</div></article>
          <article class="users-detail-card"><div class="k">权限角色</div><div class="v">${escapeHtml(role)}</div></article>
          <article class="users-detail-card"><div class="k">账号状态</div><div class="v">${current.is_active ? "启用" : "禁用"}</div></article>
          <article class="users-detail-card"><div class="k">最后登录</div><div class="v">${escapeHtml(formatShortDateTime(current.last_login_at))}</div></article>
        </div>
        <div class="questionnaire-history-empty">右侧控制区占位：后续接入权限编辑、重置密码、启停账号。</div>
      </div>
    `;
  }

  async function loadUsers(force = false) {
    if (state.users.loading) {
      return;
    }
    if (!force && state.users.loaded) {
      renderUsersPanel();
      return;
    }
    state.users.loading = true;
    renderUsersPanel();
    try {
      const data = await api("/api/users");
      state.users.list = Array.isArray(data.items) ? data.items : [];
      state.users.loaded = true;
      renderUsersPanel();
    } catch (err) {
      state.users.list = [];
      state.users.loaded = false;
      renderUsersPanel();
      showToast(err.message || "加载用户列表失败", "error");
    } finally {
      state.users.loading = false;
      renderUsersPanel();
    }
  }

  function renderInferFormat(formatObj) {
    const node = el("status-infer-format");
    if (!node) {
      return;
    }
    const payload = formatObj && typeof formatObj === "object" ? formatObj : {};
    node.textContent = JSON.stringify(payload, null, 2);
  }

  function renderSystemStatus(data) {
    const root = data && typeof data === "object" ? data : {};
    const inference = root.inference_server || {};
    const metrics = inference.metrics || {};

    const stateNode = el("status-server-state");
    const messageNode = el("status-server-message");
    const queueNode = el("status-queue-length");
    const latencyNode = el("status-latency-ms");
    const errorRateNode = el("status-error-rate");

    const online = inference.status === "online";
    if (stateNode) {
      stateNode.textContent = online ? "在线" : "离线";
      stateNode.classList.remove("online", "offline");
      stateNode.classList.add(online ? "online" : "offline");
    }
    if (messageNode) {
      messageNode.textContent = inference.message || "--";
    }
    if (queueNode) {
      queueNode.textContent = Number.isFinite(Number(inference.queue_length)) ? String(inference.queue_length) : "-";
    }
    if (latencyNode) {
      latencyNode.textContent = Number.isFinite(Number(inference.recent_latency_ms))
        ? `${Number(inference.recent_latency_ms).toFixed(1)} ms`
        : "-";
    }
    if (errorRateNode) {
      errorRateNode.textContent = Number.isFinite(Number(inference.error_rate))
        ? `${Number(inference.error_rate).toFixed(1)}%`
        : "-";
    }

    const ramTotal = numOrNull(metrics.ram_total_mb);
    const ramUsed = numOrNull(metrics.ram_used_mb);
    const ramPercentRaw = numOrNull(metrics.ram_percent);
    const ramPercent =
      ramPercentRaw !== null
        ? clamp(ramPercentRaw, 0, 100)
        : ramTotal && ramUsed !== null && ramTotal > 0
          ? clamp((ramUsed / ramTotal) * 100, 0, 100)
          : null;
    const ramFree = ramTotal !== null && ramUsed !== null ? Math.max(ramTotal - ramUsed, 0) : null;
    renderPieChart(
      "pie-ram",
      "pie-ram-center",
      "legend-ram",
      [
        { label: "已用", value: ramUsed !== null ? ramUsed : 0, color: "#2563eb", display: formatMB(ramUsed) },
        { label: "可用", value: ramFree !== null ? ramFree : 0, color: "#bfdbfe", display: formatMB(ramFree) },
      ],
      ramPercent !== null ? `${ramPercent.toFixed(1)}%` : "--"
    );

    const gpuAlloc = numOrNull(metrics.gpu_mem_allocated_mb);
    const gpuReserved = numOrNull(metrics.gpu_mem_reserved_mb);
    const gpuIdle = gpuReserved !== null && gpuAlloc !== null ? Math.max(gpuReserved - gpuAlloc, 0) : null;
    const gpuPercent =
      gpuReserved !== null && gpuReserved > 0 && gpuAlloc !== null ? clamp((gpuAlloc / gpuReserved) * 100, 0, 100) : null;
    renderPieChart(
      "pie-gpu",
      "pie-gpu-center",
      "legend-gpu",
      [
        { label: "Allocated", value: gpuAlloc !== null ? gpuAlloc : 0, color: "#7c3aed", display: formatMB(gpuAlloc) },
        { label: "Reserved余量", value: gpuIdle !== null ? gpuIdle : 0, color: "#ddd6fe", display: formatMB(gpuIdle) },
      ],
      gpuPercent !== null ? `${gpuPercent.toFixed(1)}%` : "--"
    );

    const cpuPercentRaw = numOrNull(metrics.cpu_percent);
    const cpuPercent = cpuPercentRaw !== null ? clamp(cpuPercentRaw, 0, 100) : null;
    renderPieChart(
      "pie-cpu",
      "pie-cpu-center",
      "legend-cpu",
      [
        { label: "CPU使用", value: cpuPercent !== null ? cpuPercent : 0, color: "#f59e0b", display: cpuPercent !== null ? `${cpuPercent.toFixed(1)}%` : "--" },
        { label: "空闲", value: cpuPercent !== null ? 100 - cpuPercent : 0, color: "#fde68a", display: cpuPercent !== null ? `${(100 - cpuPercent).toFixed(1)}%` : "--" },
      ],
      cpuPercent !== null ? `${cpuPercent.toFixed(1)}%` : "--"
    );

    renderStatusErrors(inference.recent_errors);
    renderInferFormat(inference.infer_response_format);
  }

  async function loadSystemStatus() {
    try {
      const data = await api("/api/system/status");
      renderSystemStatus(data);
    } catch (err) {
      renderSystemStatus({
        inference_server: {
          status: "offline",
          message: err.message || "状态获取失败",
          queue_length: null,
          recent_latency_ms: null,
          error_rate: null,
          recent_errors: [],
          metrics: {},
          infer_response_format: {},
        },
      });
    }
  }

  async function loadOverviewMetrics() {
    const cached = readOverviewCache();
    if (cached && typeof cached === "object") {
      const cachedStats = cached.stats && typeof cached.stats === "object" ? cached.stats : {};
      const cachedFeed = Array.isArray(cached.feed) ? cached.feed : [];
      const cachedSchedules = Array.isArray(cached.schedules) ? cached.schedules : [];
      setOverviewMetrics(cachedStats);
      renderOverviewLists(cachedFeed, cachedSchedules, Number(cachedStats.pending_reviews || 0));
    }

    try {
      const data = await withTimeout(api("/api/overview"), 6000);
      const stats = data && typeof data === "object" ? data.stats || {} : {};
      const feedRows = Array.isArray(data.feed) ? data.feed : [];
      const scheduleRows = Array.isArray(data.schedules) ? data.schedules : [];

      setOverviewMetrics(stats);
      renderOverviewLists(feedRows, scheduleRows, Number(stats.pending_reviews || 0));
      writeOverviewCache({
        stats,
        feed: feedRows,
        schedules: scheduleRows,
      });
    } catch (_err) {
      if (!cached) {
        setOverviewMetrics({});
        renderOverviewLists([], [], 0);
      }
    }
  }

  function startOverviewClock() {
    renderOverviewDate();
    if (state.overviewClockTimer) {
      return;
    }
    state.overviewClockTimer = window.setInterval(renderOverviewDate, 1000);
  }

  function stopOverviewClock() {
    if (!state.overviewClockTimer) {
      return;
    }
    window.clearInterval(state.overviewClockTimer);
    state.overviewClockTimer = null;
  }

  function startStatusPolling() {
    loadSystemStatus();
    if (state.statusPollTimer) {
      return;
    }
    state.statusPollTimer = window.setInterval(loadSystemStatus, 1000);
  }

  function stopStatusPolling() {
    if (!state.statusPollTimer) {
      return;
    }
    window.clearInterval(state.statusPollTimer);
    state.statusPollTimer = null;
  }

  function updateUserUI(user) {
    state.user = user || null;
    const name = userDisplayName(state.user);

    const usernameEl = el("sidebar-username");
    const avatarEl = el("sidebar-avatar");

    if (usernameEl) {
      usernameEl.textContent = name;
    }
    if (avatarEl) {
      avatarEl.textContent = name.slice(0, 1).toUpperCase();
    }
  }

  function setActiveView(viewKey) {
    const key = normalizeViewKey(viewKey);
    state.activeView = key;
    saveActiveView(key);

    document.querySelectorAll(".nav-item[data-view]").forEach((item) => {
      item.classList.toggle("active", item.dataset.view === key);
    });

    const meta = VIEW_META[key];
    const titleEl = el("placeholder-title");
    const descEl = el("placeholder-desc");
    const headerEl = el("header-title");

    if (titleEl) {
      titleEl.textContent = meta.title;
    }
    if (descEl) {
      descEl.textContent = meta.desc;
    }
    if (headerEl) {
      headerEl.textContent = `Spine FUPT · ${meta.title}`;
    }

    const stage = document.querySelector(".blank-stage");
    const isOverview = key === "overview";
    const isStatus = key === "server-status";
    const isPatients = key === "patients";
    const isReviews = key === "reviews";
    const isQuestionnaires = key === "questionnaires";
    const isChat = key === "chat";
    const isLogs = key === "logs";
    const isUsers = key === "users";
    if (stage) {
      stage.classList.toggle("overview-mode", isOverview);
      stage.classList.toggle("status-mode", isStatus);
      stage.classList.toggle("patients-mode", isPatients);
      stage.classList.toggle("reviews-mode", isReviews);
      stage.classList.toggle("questionnaires-mode", isQuestionnaires);
      stage.classList.toggle("chat-mode", isChat);
      stage.classList.toggle("logs-mode", isLogs);
      stage.classList.toggle("users-mode", isUsers);
    }

    if (isOverview) {
      startOverviewClock();
      loadOverviewMetrics();
    } else {
      stopOverviewClock();
    }

    if (isStatus) {
      startStatusPolling();
    } else {
      stopStatusPolling();
    }

    if (isPatients) {
      loadPatients(false);
    } else {
      closePatientDetailLayer();
      closePatientRegisterLayer(false);
      state.patients.detailId = null;
      state.patients.detailEditing = false;
    }

    if (isReviews) {
      if (isMobile()) {
        state.reviews.mobileDetailOpen = false;
      }
      syncReviewsMobileView();
      loadReviews(false);
    } else {
      state.reviews.mobileDetailOpen = false;
      syncReviewsMobileView();
    }

    if (isQuestionnaires) {
      loadQuestionnaires(false);
    } else {
      closeQuestionnaireCreateLayer();
      closeQuestionnaireDetailLayer();
    }

    if (isChat) {
      if (isMobile()) {
        state.questionnaires.chatMobileDetailOpen = false;
      }
      syncQuestionnaireChatDirectoryUI();
      syncQuestionnaireChatMobileView();
      loadQuestionnaireChats(false);
    } else {
      state.questionnaires.chatMobileDetailOpen = false;
      syncQuestionnaireChatMobileView();
    }

    if (isLogs) {
      loadLogs(false);
    }

    if (isUsers) {
      loadUsers(false);
    }
    syncRealtimeChatChannelSubscription();
  }

  function bindQuestionnaires() {
    syncQuestionnaireChatDirectoryUI();
    el("questionnaires-create-btn")?.addEventListener("click", () => {
      openQuestionnaireCreateLayer();
      renderQuestionnaireBuilder();
    });
    el("questionnaires-history-btn")?.addEventListener("click", () => {
      closeQuestionnaireCreateLayer();
      closeQuestionnaireDetailLayer();
      loadQuestionnaires(false);
    });
    el("questionnaires-create-back-btn")?.addEventListener("click", () => {
      closeQuestionnaireCreateLayer();
    });
    el("questionnaires-detail-back-btn")?.addEventListener("click", () => {
      closeQuestionnaireDetailLayer();
      loadQuestionnaires(false);
    });
    el("questionnaires-detail-save-btn")?.addEventListener("click", async () => {
      await saveQuestionnaireDetail();
    });
    el("questionnaires-detail-settings-btn")?.addEventListener("click", () => {
      openQuestionnaireDetailSettingsModal();
    });
    el("questionnaire-detail-settings-cancel-btn")?.addEventListener("click", () => {
      closeQuestionnaireDetailSettingsModal();
    });
    el("questionnaire-detail-settings-save-btn")?.addEventListener("click", () => {
      applyQuestionnaireDetailSettingsFromModal();
      closeQuestionnaireDetailSettingsModal();
      renderQuestionnaireDetail();
    });
    el("questionnaire-detail-settings-modal")?.addEventListener("click", (event) => {
      if (event.target.id === "questionnaire-detail-settings-modal") {
        closeQuestionnaireDetailSettingsModal();
      }
    });

    el("questionnaire-title-input")?.addEventListener("input", (event) => {
      ensureQuestionnaireDraft();
      state.questionnaires.draft.title = event.target.value || "";
    });

    const introEditor = el("questionnaire-intro-editor");
    const richBox = introEditor ? introEditor.closest(".questionnaire-rich") : null;

    introEditor?.addEventListener("input", (event) => {
      ensureQuestionnaireDraft();
      state.questionnaires.draft.introHtml = serializeQuestionnaireIntroHtml(event.target);
    });

    function syncIntroHtml() {
      ensureQuestionnaireDraft();
      state.questionnaires.draft.introHtml = serializeQuestionnaireIntroHtml(introEditor);
    }

    function insertImagesToIntro(files) {
      const imgs = Array.from(files || []).filter((f) => /^image\//i.test(f.type || ""));
      if (!imgs.length || !introEditor) {
        return;
      }
      introEditor.focus();
      let remain = imgs.length;
      imgs.forEach((file) => {
        const reader = new FileReader();
        reader.onload = () => {
          const imageWrap = createQuestionnaireEditorImageWrap(String(reader.result || ""), file.name || "image");
          insertNodeAtCaret(introEditor, imageWrap);
          const nextLine = document.createElement("p");
          nextLine.innerHTML = "<br>";
          insertNodeAtCaret(introEditor, nextLine);
          selectQuestionnaireEditorImage(introEditor, imageWrap);
          remain -= 1;
          if (remain <= 0) {
            syncIntroHtml();
          }
        };
        reader.onerror = () => {
          remain -= 1;
          if (remain <= 0) {
            syncIntroHtml();
          }
        };
        reader.readAsDataURL(file);
      });
    }

    if (introEditor && richBox) {
      const addDragStyle = (event) => {
        event.preventDefault();
        richBox.classList.add("dragover");
      };
      const removeDragStyle = () => {
        richBox.classList.remove("dragover");
      };
      introEditor.addEventListener("dragenter", addDragStyle);
      introEditor.addEventListener("dragover", addDragStyle);
      introEditor.addEventListener("dragleave", (event) => {
        event.preventDefault();
        if (!introEditor.contains(event.relatedTarget)) {
          removeDragStyle();
        }
      });
      introEditor.addEventListener("drop", (event) => {
        event.preventDefault();
        removeDragStyle();
        const files = event.dataTransfer?.files;
        if (files && files.length) {
          insertImagesToIntro(files);
        }
      });
      introEditor.addEventListener("paste", (event) => {
        const files = Array.from(event.clipboardData?.items || [])
          .map((item) => (item.kind === "file" ? item.getAsFile() : null))
          .filter((f) => f && /^image\//i.test(f.type || ""));
        if (!files.length) {
          return;
        }
        event.preventDefault();
        insertImagesToIntro(files);
      });
      introEditor.addEventListener("click", (event) => {
        const imgToolBtn = event.target.closest("[data-img-tool]");
        if (imgToolBtn) {
          const imageWrap = imgToolBtn.closest(".questionnaire-editor-image-wrap");
          if (imageWrap) {
            const action = imgToolBtn.getAttribute("data-img-tool") || "";
            const currWidth = parseFloat(imageWrap.style.width || "0") || imageWrap.getBoundingClientRect().width;
            if (action === "zoom-in") {
              setQuestionnaireImageWidth(introEditor, imageWrap, currWidth * 1.1);
            } else if (action === "zoom-out") {
              setQuestionnaireImageWidth(introEditor, imageWrap, currWidth * 0.9);
            } else if (action === "reset") {
              imageWrap.style.width = "";
            }
            syncIntroHtml();
          }
          return;
        }
        const imageWrap = event.target.closest(".questionnaire-editor-image-wrap");
        if (imageWrap && introEditor.contains(imageWrap)) {
          selectQuestionnaireEditorImage(introEditor, imageWrap);
          return;
        }
        clearQuestionnaireImageSelection(introEditor);
      });
      introEditor.addEventListener("mousedown", (event) => {
        const handle = event.target.closest(".questionnaire-image-handle[data-img-handle='se']");
        const imageWrap = handle ? handle.closest(".questionnaire-editor-image-wrap") : null;
        if (!handle || !imageWrap) {
          return;
        }
        event.preventDefault();
        event.stopPropagation();
        const startX = event.clientX;
        const startWidth = parseFloat(imageWrap.style.width || "0") || imageWrap.getBoundingClientRect().width;
        const onMove = (moveEvent) => {
          const dx = moveEvent.clientX - startX;
          setQuestionnaireImageWidth(introEditor, imageWrap, startWidth + dx);
        };
        const onUp = () => {
          window.removeEventListener("mousemove", onMove);
          window.removeEventListener("mouseup", onUp);
          syncIntroHtml();
        };
        window.addEventListener("mousemove", onMove);
        window.addEventListener("mouseup", onUp);
      });
      introEditor.addEventListener("mouseup", () => {
        syncIntroHtml();
      });
      introEditor.addEventListener("keyup", () => {
        syncIntroHtml();
      });
      normalizeQuestionnaireEditorImages(introEditor);
    }

    document.querySelectorAll(".questionnaire-tool-btn[data-q-cmd]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const cmd = btn.getAttribute("data-q-cmd") || "";
        const intro = el("questionnaire-intro-editor");
        intro?.focus();
        if (cmd) {
          document.execCommand(cmd, false);
          ensureQuestionnaireDraft();
          state.questionnaires.draft.introHtml = serializeQuestionnaireIntroHtml(intro);
        }
      });
    });

    el("questionnaire-save-btn")?.addEventListener("click", async () => {
      await saveQuestionnaireDraft();
    });

    el("questionnaires-history-list")?.addEventListener("click", async (event) => {
      const item = event.target.closest(".questionnaire-history-item[data-questionnaire-id]");
      if (!item) {
        return;
      }
      const qid = Number(item.getAttribute("data-questionnaire-id") || "0") || 0;
      if (!qid) {
        return;
      }
      await loadQuestionnaireDetail(qid);
    });
    el("questionnaire-detail-content")?.addEventListener("input", (event) => {
      const detail = state.questionnaires.detail;
      const q = detail?.questionnaire;
      if (!q) {
        return;
      }
      const titleInput = event.target.closest("#questionnaire-detail-title-input");
      if (titleInput) {
        q.title = titleInput.value || "";
        return;
      }
      const descInput = event.target.closest("#questionnaire-detail-description-input");
      if (descInput) {
        q.description = descInput.value || "";
        return;
      }
      const input = event.target.closest("[data-detail-action][data-q-id]");
      if (!input) {
        return;
      }
      const action = input.getAttribute("data-detail-action") || "";
      const qid = Number(input.getAttribute("data-q-id") || "0") || 0;
      const row = (Array.isArray(q.questions) ? q.questions : []).find((item) => Number(item.id) === qid);
      if (!row) {
        return;
      }
      if (action === "title") {
        row.title = input.value || "";
      } else if (action === "option") {
        const oi = Number(input.getAttribute("data-opt-index") || "-1");
        if (!Array.isArray(row.options)) {
          row.options = [];
        }
        if (oi >= 0) {
          row.options[oi] = input.value || "";
        }
      }
    });
    el("questionnaire-detail-content")?.addEventListener("click", (event) => {
      const btn = event.target.closest("[data-detail-action][data-q-id]");
      const q = state.questionnaires.detail?.questionnaire;
      if (!btn || !q) {
        return;
      }
      const action = btn.getAttribute("data-detail-action") || "";
      const qid = Number(btn.getAttribute("data-q-id") || "0") || 0;
      if (!qid) {
        return;
      }
      const list = Array.isArray(q.questions) ? q.questions : [];
      const idx = list.findIndex((item) => Number(item.id) === qid);
      if (idx < 0) {
        return;
      }
      if (action === "remove-question") {
        list.splice(idx, 1);
        renderQuestionnaireDetail();
        return;
      }
      if (action === "remove-option") {
        const row = list[idx];
        const oi = Number(btn.getAttribute("data-opt-index") || "-1");
        if (!Array.isArray(row.options)) {
          row.options = [];
        }
        if (oi >= 0 && row.options.length > 2) {
          row.options.splice(oi, 1);
          renderQuestionnaireDetail();
        } else {
          showToast("选项题至少保留2个选项", "error");
        }
      }
    });
    el("questionnaires-chat-list")?.addEventListener("click", async (event) => {
      if (state.questionnaires.directoryMode) {
        const userItem = event.target.closest(".questionnaires-chat-item[data-dir-kind][data-dir-id]");
        if (!userItem) {
          return;
        }
        const kind = userItem.getAttribute("data-dir-kind") || "doctor";
        const id = Number(userItem.getAttribute("data-dir-id") || "0") || 0;
        if (!id) {
          return;
        }
        await startConversationFromDirectory(kind, id);
        return;
      }
      const item = event.target.closest(".questionnaires-chat-item[data-chat-id]");
      if (!item) {
        return;
      }
      const cid = Number(item.getAttribute("data-chat-id") || "0") || 0;
      if (!cid) {
        return;
      }
      await selectQuestionnaireChat(cid);
    });
    el("questionnaires-chat-back-btn")?.addEventListener("click", () => {
      state.questionnaires.chatMobileDetailOpen = false;
      syncQuestionnaireChatMobileView();
    });
    el("questionnaires-chat-query-btn")?.addEventListener("click", async () => {
      await setQuestionnaireChatDirectoryMode(!state.questionnaires.directoryMode);
    });
    el("questionnaires-chat-search-input")?.addEventListener("input", (event) => {
      state.questionnaires.directoryKeyword = event.target.value || "";
      renderQuestionnaireChatList();
    });
    el("questionnaires-chat-title-btn")?.addEventListener("click", async (event) => {
      const btn = event.currentTarget;
      const patientId = Number(btn?.getAttribute("data-patient-id") || "0") || 0;
      if (!patientId) {
        return;
      }
      setActiveView("patients");
      await loadPatientDetail(patientId);
    });
    el("questionnaires-chat-send-btn")?.addEventListener("click", async () => {
      await sendQuestionnaireChatMessage();
    });
    el("questionnaires-chat-input")?.addEventListener("keydown", async (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        await sendQuestionnaireChatMessage();
      }
    });
    el("questionnaires-detail-share-btn")?.addEventListener("click", async () => {
      await openQuestionnaireAssignModal();
    });
    el("questionnaires-detail-delete-btn")?.addEventListener("click", async () => {
      const qid = Number(state.questionnaires.detailId || 0) || 0;
      if (!qid) {
        return;
      }
      if (!window.confirm("确认删除该问卷？")) {
        return;
      }
      try {
        await api(`/api/questionnaires/${qid}`, { method: "DELETE" });
        showToast("问卷已删除", "success");
        closeQuestionnaireDetailLayer();
        await loadQuestionnaires(true);
      } catch (err) {
        showToast(err.message || "删除问卷失败", "error");
      }
    });
    el("questionnaire-assign-close-btn")?.addEventListener("click", closeQuestionnaireAssignModal);
    el("questionnaire-assign-cancel-btn")?.addEventListener("click", closeQuestionnaireAssignModal);
    el("questionnaire-assign-modal")?.addEventListener("click", (event) => {
      if (event.target.id === "questionnaire-assign-modal") {
        closeQuestionnaireAssignModal();
      }
    });
    el("questionnaire-assign-search-input")?.addEventListener("input", (event) => {
      state.questionnaires.assignSearch = event.target.value || "";
      renderQuestionnaireAssignList();
    });
    el("questionnaire-assign-list")?.addEventListener("click", (event) => {
      if (event.target.closest("input[data-patient-checkbox][data-patient-id]")) {
        return;
      }
      const row = event.target.closest(".questionnaire-assign-item[data-patient-id]");
      if (!row) {
        return;
      }
      const pid = Number(row.getAttribute("data-patient-id") || "0") || 0;
      if (!pid) {
        return;
      }
      const selected = new Set((state.questionnaires.assignSelectedIds || []).map((x) => Number(x) || 0).filter((x) => x > 0));
      if (selected.has(pid)) {
        selected.delete(pid);
      } else {
        selected.add(pid);
      }
      state.questionnaires.assignSelectedIds = [...selected];
      renderQuestionnaireAssignList();
    });
    el("questionnaire-assign-list")?.addEventListener("change", (event) => {
      const checkbox = event.target.closest("input[data-patient-checkbox][data-patient-id]");
      if (!checkbox) {
        return;
      }
      const pid = Number(checkbox.getAttribute("data-patient-id") || "0") || 0;
      if (!pid) {
        return;
      }
      const selected = new Set((state.questionnaires.assignSelectedIds || []).map((x) => Number(x) || 0).filter((x) => x > 0));
      if (checkbox.checked) {
        selected.add(pid);
      } else {
        selected.delete(pid);
      }
      state.questionnaires.assignSelectedIds = [...selected];
      renderQuestionnaireAssignList();
    });
    el("questionnaire-assign-submit-btn")?.addEventListener("click", async () => {
      await submitQuestionnaireAssign();
    });

    el("questionnaire-questions-list")?.addEventListener("click", (event) => {
      const listActionBtn = event.target.closest("[data-q-list-action]");
      if (listActionBtn) {
        const listAction = listActionBtn.getAttribute("data-q-list-action") || "";
        if (listAction === "add-choice") {
          addDraftQuestion("choice");
          return;
        }
        if (listAction === "add-blank") {
          addDraftQuestion("blank");
          return;
        }
      }
      const btn = event.target.closest("[data-q-action][data-q-id]");
      if (!btn) {
        return;
      }
      const action = btn.getAttribute("data-q-action") || "";
      const qid = Number(btn.getAttribute("data-q-id") || "0") || 0;
      if (!qid) {
        return;
      }
      ensureQuestionnaireDraft();
      const qidx = state.questionnaires.draft.questions.findIndex((q) => Number(q.id) === qid);
      if (qidx < 0) {
        return;
      }
      const q = state.questionnaires.draft.questions[qidx];

      if (action === "remove") {
        state.questionnaires.draft.questions.splice(qidx, 1);
        renderQuestionnaireBuilder();
        return;
      }
      if (action === "add-option" && q.type === "choice") {
        if (!Array.isArray(q.options)) {
          q.options = [];
        }
        q.options.push(`选项${q.options.length + 1}`);
        renderQuestionnaireBuilder();
        return;
      }
      if (action === "remove-option" && q.type === "choice") {
        const oi = Number(btn.getAttribute("data-opt-index") || "-1");
        if (oi >= 0 && Array.isArray(q.options) && q.options.length > 1) {
          q.options.splice(oi, 1);
          renderQuestionnaireBuilder();
        }
        return;
      }
      if (action === "setting" && q.type === "blank") {
        openQuestionnaireSettingModal(qid);
      }
    });

    el("questionnaire-questions-list")?.addEventListener("input", (event) => {
      const input = event.target.closest("[data-q-action][data-q-id]");
      if (!input) {
        return;
      }
      const action = input.getAttribute("data-q-action") || "";
      const qid = Number(input.getAttribute("data-q-id") || "0") || 0;
      if (!qid) {
        return;
      }
      ensureQuestionnaireDraft();
      const q = state.questionnaires.draft.questions.find((row) => Number(row.id) === qid);
      if (!q) {
        return;
      }
      if (action === "title") {
        q.title = input.value || "";
        return;
      }
      if (action === "option" && q.type === "choice") {
        const oi = Number(input.getAttribute("data-opt-index") || "-1");
        if (oi >= 0) {
          if (!Array.isArray(q.options)) {
            q.options = [];
          }
          q.options[oi] = input.value || "";
        }
      }
    });

    el("questionnaire-constraint-cancel-btn")?.addEventListener("click", closeQuestionnaireSettingModal);
    el("questionnaire-constraint-save-btn")?.addEventListener("click", saveQuestionnaireSettingModal);
    el("questionnaire-blank-setting-modal")?.addEventListener("click", (event) => {
      if (event.target.id === "questionnaire-blank-setting-modal") {
        closeQuestionnaireSettingModal();
      }
    });
  }

  function bindNav() {
    document.querySelectorAll(".nav-item[data-view]").forEach((item) => {
      item.addEventListener("click", () => {
        setActiveView(item.dataset.view || "overview");
        if (isMobile()) {
          el("sidebar")?.classList.remove("mobile-open");
        }
      });
    });
  }

  async function handleLoginSubmit(event) {
    event.preventDefault();

    const username = (el("login-username")?.value || "").trim();
    const password = el("login-password")?.value || "";

    if (!username || !password) {
      showLoginError("请输入用户名和密码");
      return;
    }

    clearLoginError();
    setLoginLoading(true);

    try {
      const data = await api("/api/auth/login", {
        method: "POST",
        body: { username, password },
      });
      updateUserUI(data.user);
      setAuthVisibility(true);
      loadReviewViewerTransform();
      ensureRealtimeSystemWs();
      loadQuestionnaireChats(true);
      setActiveView(state.activeView);
      showToast("登录成功", "success");
    } catch (err) {
      showLoginError(err.message || "登录失败");
    } finally {
      setLoginLoading(false);
    }
  }

  async function handleLogout() {
    try {
      await api("/api/auth/logout", { method: "POST" });
    } catch (_err) {
      // Keep local reset even when API fails.
    }

    state.user = null;
    state.questionnaires = {
      loaded: false,
      loading: false,
      saving: false,
      items: [],
      chatsLoaded: false,
      chatsLoading: false,
      chats: [],
      chatSelectedId: null,
      chatMessagesMap: {},
      chatMessagesLoading: false,
      realtimeChatChannel: "",
      chatReadTimers: {},
      directoryMode: false,
      directoryLoading: false,
      directoryLoaded: false,
      directoryItems: [],
      directoryKeyword: "",
      detailLoading: false,
      detailId: null,
      detail: null,
      detailSettingsOpen: false,
      assignModalOpen: false,
      assignLoading: false,
      assignSubmitting: false,
      assignCandidates: [],
      assignSearch: "",
      assignSelectedIds: [],
      createMode: false,
      settingQuestionId: null,
      draft: {
        title: "",
        introHtml: "",
        questions: [],
        nextId: 1,
      },
    };
    state.reviews = {
      loaded: false,
      loading: false,
      submitting: false,
      deletingId: null,
      list: [],
      selectedId: null,
      detailMap: {},
      noteDraftMap: {},
      viewer: {
        scale: 1,
        tx: 0,
        ty: 0,
        imageSource: "ai",
        hasAi: false,
        hasRaw: false,
        minScale: 0.3,
        maxScale: 6,
        dragging: false,
        startX: 0,
        startY: 0,
        startTx: 0,
        startTy: 0,
      },
    };
    closeReviewDeleteModal();
    state.patients = {
      loaded: false,
      loading: false,
      list: [],
      search: "",
      sortKey: "updated_at",
      sortDir: "desc",
      detailId: null,
      detailTab: "basic",
      detailEditing: false,
      detailMap: {},
      listScrollTop: 0,
      register: {
        active: false,
        token: "",
        channel: "",
        formState: {},
        focusField: "",
        status: "",
        ws: null,
        wsReady: false,
        wsShouldReconnect: false,
        applyingRemote: false,
        fieldTimers: {},
      },
    };
    state.logs = {
      loaded: false,
      loading: false,
      items: [],
    };
    state.users = {
      loaded: false,
      loading: false,
      list: [],
      selectedId: null,
    };
    teardownRealtimeSystemWs();
    stopOverviewClock();
    stopStatusPolling();
    setOverviewMetrics(NaN, NaN);
    renderOverviewLists([], [], 0);
    closePatientDetailLayer();
    closePatientRegisterLayer(false);
    renderPatientsList();
    const searchInput = el("patients-search-input");
    if (searchInput) {
      searchInput.value = "";
    }
    clearLoginError();
    setAuthVisibility(false);
    showToast("已退出登录", "info");
  }

  function bindUserMenu() {
    const button = el("user-menu-button");
    const menu = el("user-menu");

    if (!button || !menu) {
      return;
    }

    button.addEventListener("click", (event) => {
      if (event.target.closest("#logout-btn") || event.target.closest("#refresh-list-btn")) {
        return;
      }
      menu.classList.toggle("active");
      event.stopPropagation();
    });

    document.addEventListener("click", (event) => {
      if (!button.contains(event.target)) {
        menu.classList.remove("active");
      }
    });

    el("refresh-list-btn")?.addEventListener("click", () => {
      menu.classList.remove("active");
      if (state.activeView === "patients") {
        loadPatients(true);
      } else if (state.activeView === "reviews") {
        loadReviews(true);
      } else if (state.activeView === "questionnaires") {
        loadQuestionnaires(true);
      } else if (state.activeView === "chat") {
        loadQuestionnaireChats(true);
      } else if (state.activeView === "logs") {
        loadLogs(true);
      } else if (state.activeView === "overview") {
        loadOverviewMetrics();
      } else if (state.activeView === "server-status") {
        loadSystemStatus();
      } else {
        setActiveView(state.activeView);
      }
      showToast("已刷新", "info");
    });
  }

  function bindSidebarToggles() {
    const sidebar = el("sidebar");

    el("toggle-sidebar")?.addEventListener("click", () => {
      if (!sidebar) {
        return;
      }
      if (isMobile()) {
        sidebar.classList.toggle("mobile-open");
      } else {
        sidebar.classList.toggle("collapsed");
      }
    });

    el("toggle-sidebar-mobile")?.addEventListener("click", () => {
      sidebar?.classList.remove("mobile-open");
    });

    el("sidebar-backdrop")?.addEventListener("click", () => {
      sidebar?.classList.remove("mobile-open");
    });
  }

  function queueRealtimeRefresh() {
    const rt = state.realtime;
    if (rt.refreshTimer) {
      return;
    }
    rt.refreshTimer = window.setTimeout(() => {
      rt.refreshTimer = null;
      state.logs.loaded = false;
      state.patients.loaded = false;
      state.reviews.loaded = false;

      if (state.activeView === "patients") {
        loadPatients(true);
      } else if (state.activeView === "reviews") {
        loadReviews(true);
      } else if (state.activeView === "chat") {
        loadQuestionnaireChats(true);
      } else if (state.activeView === "logs") {
        loadLogs(true);
      } else if (state.activeView === "overview") {
        loadOverviewMetrics();
      } else if (state.questionnaires.chatsLoaded) {
        loadQuestionnaireChats(true);
      }
    }, 320);
  }

  function queueRealtimeChatRefresh() {
    if (!canAccessChatModule()) {
      return;
    }
    const rt = state.realtime;
    if (rt.chatRefreshTimer) {
      return;
    }
    rt.chatRefreshTimer = window.setTimeout(() => {
      rt.chatRefreshTimer = null;
      loadQuestionnaireChats(true);
    }, 260);
  }

  function handleRealtimeSystemMessage(msg) {
    if (!msg || typeof msg !== "object") {
      return;
    }
    if (msg.type === "chat_message") {
      handleRealtimeChatMessage(msg);
      return;
    }
    if (msg.type === "toast") {
      const level = String(msg.level || "info").toLowerCase();
      const toastType = level === "warn" ? "warn" : level === "error" ? "error" : level === "success" ? "success" : "info";
      const title = msg.title ? `${msg.title}：` : "";
      showToast(`${title}${msg.message || ""}`, toastType);
      queueRealtimeChatRefresh();
      return;
    }
    if (msg.type === "feed_new") {
      queueRealtimeRefresh();
      queueRealtimeChatRefresh();
    }
  }

  function teardownRealtimeSystemWs() {
    const rt = state.realtime;
    rt.shouldReconnect = false;
    rt.ready = false;
    if (rt.reconnectTimer) {
      window.clearTimeout(rt.reconnectTimer);
      rt.reconnectTimer = null;
    }
    if (rt.refreshTimer) {
      window.clearTimeout(rt.refreshTimer);
      rt.refreshTimer = null;
    }
    if (rt.chatRefreshTimer) {
      window.clearTimeout(rt.chatRefreshTimer);
      rt.chatRefreshTimer = null;
    }
    if (rt.ws && rt.ws.readyState === WebSocket.OPEN) {
      try {
        rt.ws.send(JSON.stringify({ type: "unsubscribe", channel: "system" }));
      } catch (_err) {
        // ignore
      }
    }
    if (rt.ws) {
      try {
        rt.ws.close();
      } catch (_err) {
        // ignore
      }
    }
    rt.ws = null;
  }

  function ensureRealtimeSystemWs() {
    if (!state.user) {
      return;
    }
    const rt = state.realtime;
    if (rt.ws && (rt.ws.readyState === WebSocket.OPEN || rt.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    rt.shouldReconnect = true;
    const ws = new WebSocket(getWsUrl());
    rt.ws = ws;

    ws.addEventListener("open", () => {
      rt.ready = true;
      ws.send(
        JSON.stringify({
          type: "hello",
          kind: "doctor",
          id: state.user ? state.user.id : null,
          name: userDisplayName(state.user),
        })
      );
      ws.send(JSON.stringify({ type: "subscribe", channel: "system" }));
      state.questionnaires.realtimeChatChannel = "";
      syncRealtimeChatChannelSubscription();
    });

    ws.addEventListener("message", (event) => {
      try {
        const msg = JSON.parse(event.data || "{}");
        handleRealtimeSystemMessage(msg);
      } catch (_err) {
        // ignore parse error
      }
    });

    ws.addEventListener("close", () => {
      rt.ready = false;
      rt.ws = null;
      if (!rt.shouldReconnect || !state.user) {
        return;
      }
      if (rt.reconnectTimer) {
        window.clearTimeout(rt.reconnectTimer);
      }
      rt.reconnectTimer = window.setTimeout(() => {
        rt.reconnectTimer = null;
        ensureRealtimeSystemWs();
      }, 1200);
    });

    ws.addEventListener("error", () => {
      rt.ready = false;
    });
  }

  function bindStaticActions() {
    el("logout-btn")?.addEventListener("click", async () => {
      el("user-menu")?.classList.remove("active");
      await handleLogout();
    });
  }

  function bindPatients() {
    const searchInput = el("patients-search-input");
    const addBtn = el("patients-add-btn");
    const list = el("patients-list");
    const backBtn = el("patients-back-btn");
    const tabBasicBtn = el("patients-tab-basic");
    const tabStatusBtn = el("patients-tab-status");
    const regBackBtn = el("patients-register-back-btn");
    const regCopyBtn = el("register-copy-link-btn");
    const regSubmitBtn = el("register-submit-btn");
    const regForm = el("register-form");

    if (searchInput) {
      searchInput.addEventListener("input", () => {
        state.patients.search = searchInput.value || "";
        renderPatientsList();
      });
    }

    addBtn?.addEventListener("click", startPatientRegistration);
    regBackBtn?.addEventListener("click", () => closePatientRegisterLayer(false));
    regCopyBtn?.addEventListener("click", async () => {
      const link = el("register-link-input")?.value || "";
      if (!link) {
        return;
      }
      try {
        await navigator.clipboard.writeText(link);
        showToast("登记链接已复制", "success");
      } catch (_err) {
        showToast("复制失败，请手动复制", "warn");
      }
    });
    regSubmitBtn?.addEventListener("click", submitPatientRegistrationFromDoctor);

    regForm?.querySelectorAll("[data-reg-field]").forEach((input) => {
      input.addEventListener("focus", () => {
        const field = (input.getAttribute("data-reg-field") || "").trim();
        if (!field) {
          return;
        }
        setRegisterFocus(field);
        syncRegisterFocus(field);
      });
      input.addEventListener("input", () => {
        const field = (input.getAttribute("data-reg-field") || "").trim();
        if (!field) {
          return;
        }
        syncRegisterFieldDebounced(field, input.value);
      });
      if (input.tagName === "SELECT") {
        input.addEventListener("change", () => {
          const field = (input.getAttribute("data-reg-field") || "").trim();
          if (!field) {
            return;
          }
          syncRegisterFieldDebounced(field, input.value);
        });
      }
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        closePatientRegisterLayer(false);
      }
    });

    if (list) {
      list.addEventListener("click", (event) => {
        const sortBtn = event.target.closest("button[data-sort-key]");
        if (sortBtn) {
          updateSort(sortBtn.dataset.sortKey);
          return;
        }

        const deleteBtn = event.target.closest("button[data-action='delete']");
        if (deleteBtn) {
          event.stopPropagation();
          const row = deleteBtn.closest(".patient-row");
          const id = row?.dataset?.patientId;
          if (id) {
            deletePatient(id);
          }
          return;
        }

        const row = event.target.closest(".patient-row");
        const id = row?.dataset?.patientId;
        if (id) {
          loadPatientDetail(id);
        }
      });
    }

    backBtn?.addEventListener("click", backToPatientList);
    tabBasicBtn?.addEventListener("click", () => {
      if (!state.patients.detailId) {
        return;
      }
      state.patients.detailTab = "basic";
      const detail = state.patients.detailMap[state.patients.detailId];
      renderPatientDetail(detail || null);
    });
    tabStatusBtn?.addEventListener("click", () => {
      if (!state.patients.detailId) {
        return;
      }
      state.patients.detailTab = "status";
      const detail = state.patients.detailMap[state.patients.detailId];
      renderPatientDetail(detail || null);
    });
  }

  function bindReviews() {
    const list = el("reviews-list");
    const canvas = el("reviews-canvas");
    const img = el("reviews-image");
    const viewer = state.reviews.viewer;

    el("reviews-mobile-back-btn")?.addEventListener("click", () => {
      state.reviews.mobileDetailOpen = false;
      syncReviewsMobileView();
    });

    list?.addEventListener("click", (event) => {
      const actionBtn = event.target.closest("button[data-review-action]");
      if (actionBtn) {
        event.stopPropagation();
        const examId = Number(actionBtn.getAttribute("data-exam-id") || "0") || 0;
        const action = actionBtn.getAttribute("data-review-action") || "";
        if (!examId) {
          return;
        }
        if (action === "manual") {
          openReviewReclassifyModal(examId);
          return;
        }
        if (action === "approve") {
          approveReview(examId);
          return;
        }
        if (action === "delete") {
          openReviewDeleteModal(examId);
          return;
        }
      }
      if (event.target.closest("[data-review-note-input]")) {
        return;
      }
      const item = event.target.closest(".review-item[data-exam-id]");
      if (!item) {
        return;
      }
      const id = Number(item.dataset.examId) || 0;
      if (!id) {
        return;
      }
      selectReview(id);
    });

    list?.addEventListener("input", (event) => {
      const input = event.target.closest("textarea[data-review-note-input]");
      if (!input) {
        return;
      }
      const examId = Number(input.getAttribute("data-exam-id") || "0") || 0;
      if (!examId) {
        return;
      }
      state.reviews.noteDraftMap[examId] = input.value || "";
    });

    canvas?.addEventListener(
      "wheel",
      (event) => {
        event.preventDefault();
        if (!img || !img.getAttribute("src")) {
          return;
        }
        const zoomStep = event.deltaY < 0 ? 1.1 : 0.9;
        viewer.scale = clamp(viewer.scale * zoomStep, viewer.minScale, viewer.maxScale);
        applyReviewImageTransform();
      },
      { passive: false }
    );

    canvas?.addEventListener("mousedown", (event) => {
      if (!img || !img.getAttribute("src")) {
        return;
      }
      viewer.dragging = true;
      viewer.startX = event.clientX;
      viewer.startY = event.clientY;
      viewer.startTx = viewer.tx;
      viewer.startTy = viewer.ty;
      canvas.classList.add("dragging");
      event.preventDefault();
    });

    window.addEventListener("mousemove", (event) => {
      if (!viewer.dragging) {
        return;
      }
      viewer.tx = viewer.startTx + (event.clientX - viewer.startX);
      viewer.ty = viewer.startTy + (event.clientY - viewer.startY);
      applyReviewImageTransform();
    });

    window.addEventListener("mouseup", () => {
      if (!viewer.dragging) {
        return;
      }
      viewer.dragging = false;
      canvas?.classList.remove("dragging");
    });

    document.querySelectorAll(".review-tool-btn[data-review-tool]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const tool = btn.getAttribute("data-review-tool") || "";
        if (tool === "zoom-in") {
          viewer.scale = clamp(viewer.scale * 1.1, viewer.minScale, viewer.maxScale);
          applyReviewImageTransform();
          return;
        }
        if (tool === "zoom-out") {
          viewer.scale = clamp(viewer.scale * 0.9, viewer.minScale, viewer.maxScale);
          applyReviewImageTransform();
          return;
        }
        if (tool === "share") {
          showToast("分享功能占位，后续接入", "info");
          return;
        }
        if (tool === "switch") {
          const examId = Number(state.reviews.selectedId) || 0;
          const detail = examId ? state.reviews.detailMap[examId] : null;
          if (!detail) {
            showToast("请先选择复核影像", "warn");
            return;
          }
          const candidates = getReviewImageCandidates(detail);
          if (!(candidates.hasAi && candidates.hasRaw)) {
            showToast("暂无可切换的原图/AI图", "warn");
            return;
          }
          const nextSource = state.reviews.viewer.imageSource === "ai" ? "raw" : "ai";
          updateReviewViewerImage(detail, nextSource, { keepTransform: true });
          showToast(nextSource === "raw" ? "已切换为原图" : "已切换为AI图", "info");
          return;
        }
        showToast("工具栏功能占位，后续接入", "info");
      });
    });

    el("review-delete-cancel-btn")?.addEventListener("click", closeReviewDeleteModal);
    el("review-delete-confirm-btn")?.addEventListener("click", async () => {
      await confirmDeleteReview();
    });
    el("review-delete-modal")?.addEventListener("click", (event) => {
      if (event.target.id === "review-delete-modal") {
        closeReviewDeleteModal();
      }
    });

    el("review-reclassify-cancel-btn")?.addEventListener("click", closeReviewReclassifyModal);
    el("review-reclassify-confirm-btn")?.addEventListener("click", async () => {
      await confirmReviewReclassify();
    });
    el("review-reclassify-modal")?.addEventListener("click", (event) => {
      if (event.target.id === "review-reclassify-modal") {
        closeReviewReclassifyModal();
      }
    });

  }

  function bindUsers() {
    el("users-list")?.addEventListener("click", (event) => {
      const item = event.target.closest(".users-item[data-user-id]");
      if (!item) {
        return;
      }
      const uid = Number(item.getAttribute("data-user-id") || "0") || 0;
      if (!uid) {
        return;
      }
      state.users.selectedId = uid;
      renderUsersPanel();
    });
  }

  async function restoreSession() {
    try {
      const data = await api("/api/auth/session");
      if (!data.authenticated) {
        setAuthVisibility(false);
        return;
      }

      updateUserUI(data.user);
      setAuthVisibility(true);
      loadReviewViewerTransform();
      ensureRealtimeSystemWs();
      loadQuestionnaireChats(true);
      setActiveView(state.activeView);
    } catch (_err) {
      setAuthVisibility(false);
    }
  }

  function bindLoginForm() {
    const form = el("login-form");
    if (form) {
      form.addEventListener("submit", handleLoginSubmit);
    }
  }

  function boot() {
    state.activeView = readActiveView();
    loadReviewViewerTransform();
    bindLoginForm();
    bindUserMenu();
    bindSidebarToggles();
    bindStaticActions();
    bindPatients();
    bindReviews();
    bindQuestionnaires();
    bindUsers();
    bindNav();
    window.addEventListener("resize", () => {
      if (!isMobile()) {
        state.questionnaires.chatMobileDetailOpen = false;
        state.reviews.mobileDetailOpen = false;
      }
      syncQuestionnaireChatMobileView();
      syncReviewsMobileView();
    });
    setActiveView(state.activeView);
    restoreSession();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
