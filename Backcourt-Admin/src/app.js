import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signInWithPopup,
  signInWithRedirect,
  signOut,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import {
  collection,
  doc,
  getDoc,
  getFirestore,
  limit,
  onSnapshot,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-firestore.js";
import { firebaseConfig } from "./firebase-config.js";

const firebaseApp = initializeApp(firebaseConfig);
const auth = getAuth(firebaseApp);
const db = getFirestore(firebaseApp);
const googleProvider = new GoogleAuthProvider();
googleProvider.setCustomParameters({ prompt: "select_account" });

const views = {
  loading: document.querySelector("#loading-view"),
  login: document.querySelector("#login-view"),
  denied: document.querySelector("#denied-view"),
  dashboard: document.querySelector("#dashboard-view"),
};

const elements = {
  googleLogin: document.querySelector("#google-login"),
  emailForm: document.querySelector("#email-login-form"),
  email: document.querySelector("#email"),
  password: document.querySelector("#password"),
  loginError: document.querySelector("#login-error"),
  deniedEmail: document.querySelector("#denied-email"),
  deniedLogout: document.querySelector("#denied-logout"),
  logout: document.querySelector("#logout-button"),
  sidebarAvatar: document.querySelector("#sidebar-avatar"),
  sidebarName: document.querySelector("#sidebar-name"),
  sidebarRole: document.querySelector("#sidebar-role"),
  navCourt: document.querySelector("#nav-court"),
  navContent: document.querySelector("#nav-content"),
  navRelease: document.querySelector("#nav-release"),
  navPending: document.querySelector("#nav-pending-count"),
  navContentCount: document.querySelector("#nav-content-count"),
  workspaceEyebrow: document.querySelector("#workspace-eyebrow"),
  workspaceTitle: document.querySelector("#workspace-title"),
  statPending: document.querySelector("#stat-pending"),
  statHold: document.querySelector("#stat-hold"),
  statCompleted: document.querySelector("#stat-completed"),
  statToday: document.querySelector("#stat-today"),
  filterPending: document.querySelector("#filter-pending"),
  filterHold: document.querySelector("#filter-hold"),
  filterCompleted: document.querySelector("#filter-completed"),
  resultCount: document.querySelector("#result-count"),
  reportsList: document.querySelector("#reports-list"),
  reportDetail: document.querySelector("#report-detail"),
  search: document.querySelector("#search-input"),
  searchControl: document.querySelector("#search-control"),
  sync: document.querySelector("#sync-indicator"),
  reportsStats: document.querySelector("#reports-stats"),
  reportsWorkspace: document.querySelector("#reports-workspace"),
  releaseWorkspace: document.querySelector("#release-workspace"),
  releaseForm: document.querySelector("#release-form"),
  releaseMaintenance: document.querySelector("#release-maintenance"),
  releaseMaintenanceMessage: document.querySelector("#release-maintenance-message"),
  releaseMaintenanceEnds: document.querySelector("#release-maintenance-ends"),
  releaseIosMin: document.querySelector("#release-ios-min"),
  releaseIosLatest: document.querySelector("#release-ios-latest"),
  releaseIosUrl: document.querySelector("#release-ios-url"),
  releaseAndroidMin: document.querySelector("#release-android-min"),
  releaseAndroidLatest: document.querySelector("#release-android-latest"),
  releaseAndroidUrl: document.querySelector("#release-android-url"),
  releaseUpdateMessage: document.querySelector("#release-update-message"),
  releaseSave: document.querySelector("#release-save"),
  releaseUpdated: document.querySelector("#release-updated"),
  releaseStateDot: document.querySelector("#release-state-dot"),
  releaseStateLabel: document.querySelector("#release-state-label"),
  releaseNavState: document.querySelector("#release-nav-state"),
  dialog: document.querySelector("#decision-dialog"),
  decisionForm: document.querySelector("#decision-form"),
  dialogTitle: document.querySelector("#dialog-title"),
  dialogDescription: document.querySelector("#dialog-description"),
  dialogSubmit: document.querySelector("#dialog-submit"),
  dialogClose: document.querySelector("#dialog-close"),
  dialogCancel: document.querySelector("#dialog-cancel"),
  note: document.querySelector("#resolution-note"),
  noteCount: document.querySelector("#note-count"),
  toast: document.querySelector("#toast"),
};

const state = {
  user: null,
  profile: null,
  reports: [],
  filter: "pending",
  search: "",
  selectedId: null,
  selectedCourt: null,
  unsubscribe: null,
  unsubscribeConfig: null,
  processing: false,
  preview: false,
  previewCourtReports: [],
  mode: "court",
};

const typeMeta = {
  name: { label: "코트명 수정", icon: "Aa", className: "" },
  duplicate: { label: "중복 코트", icon: "⧉", className: "type-icon--duplicate" },
  closed: { label: "폐쇄 코트", icon: "×", className: "type-icon--closed" },
  new_court: { label: "새 코트", icon: "+", className: "" },
};

const statusMeta = {
  pending: { label: "대기", className: "" },
  on_hold: { label: "보류", className: "status-pill--hold" },
  approved: { label: "승인", className: "status-pill--approved" },
  rejected: { label: "반려", className: "status-pill--rejected" },
};

function showView(name) {
  Object.entries(views).forEach(([key, element]) => {
    element.classList.toggle("hidden", key !== name);
  });
}

function setLoginBusy(busy) {
  elements.googleLogin.disabled = busy;
  elements.emailForm.querySelector("button[type='submit']").disabled = busy;
}

function friendlyAuthError(error) {
  const code = error?.code ?? "";
  if (code.includes("invalid-credential") || code.includes("wrong-password")) {
    return "이메일 또는 비밀번호를 확인해주세요.";
  }
  if (code.includes("user-not-found")) return "등록되지 않은 계정이에요.";
  if (code.includes("too-many-requests")) return "로그인 시도가 많아요. 잠시 후 다시 시도해주세요.";
  if (code.includes("popup-closed")) return "로그인 창이 닫혔어요.";
  return "로그인하지 못했어요. 잠시 후 다시 시도해주세요.";
}

async function loginWithGoogle() {
  elements.loginError.textContent = "";
  setLoginBusy(true);
  try {
    await signInWithPopup(auth, googleProvider);
  } catch (error) {
    if (error?.code === "auth/popup-blocked") {
      await signInWithRedirect(auth, googleProvider);
      return;
    }
    elements.loginError.textContent = friendlyAuthError(error);
  } finally {
    setLoginBusy(false);
  }
}

async function loginWithEmail(event) {
  event.preventDefault();
  elements.loginError.textContent = "";
  setLoginBusy(true);
  try {
    await signInWithEmailAndPassword(auth, elements.email.value.trim(), elements.password.value);
  } catch (error) {
    elements.loginError.textContent = friendlyAuthError(error);
  } finally {
    setLoginBusy(false);
  }
}

async function logout() {
  if (state.unsubscribe) state.unsubscribe();
  if (state.unsubscribeConfig) state.unsubscribeConfig();
  state.unsubscribe = null;
  state.unsubscribeConfig = null;
  state.reports = [];
  state.selectedId = null;
  await signOut(auth);
}

async function handleAuthState(user) {
  if (state.unsubscribe) state.unsubscribe();
  if (state.unsubscribeConfig) state.unsubscribeConfig();
  state.unsubscribe = null;
  state.unsubscribeConfig = null;
  state.user = user;
  state.profile = null;

  if (!user) {
    showView("login");
    return;
  }

  showView("loading");
  try {
    const profileSnapshot = await getDoc(doc(db, "users", user.uid));
    const profile = profileSnapshot.data() ?? {};
    const role = profile.role ?? "user";
    if (role !== "operator" && role !== "admin") {
      elements.deniedEmail.textContent = user.email ?? "현재 로그인한";
      showView("denied");
      return;
    }

    state.profile = profile;
    hydrateOperator(user, profile);
    showView("dashboard");
    subscribeToReleaseConfig();
    if (state.mode !== "release") subscribeToReports();
  } catch (error) {
    console.error(error);
    elements.deniedEmail.textContent = user.email ?? "현재 로그인한";
    showView("denied");
  }
}

function startLocalPreview() {
  const now = Date.now();
  const dateAt = (minutesAgo) => ({ toDate: () => new Date(now - minutesAgo * 60_000) });
  state.preview = true;
  state.user = { uid: "preview-operator", displayName: "빽코트 운영자", email: "admin@backcourt.kr" };
  state.profile = { displayName: "빽코트 운영자", role: "operator" };
  state.reports = [
    {
      id: "preview-name-request",
      courtId: "osm_way_112233",
      currentName: "잠실2동 농구장",
      requestedName: "잠실한강공원 농구장",
      reason: "현장 안내판에 잠실한강공원 농구장으로 표시되어 있습니다.",
      requesterName: "농구하는민수",
      uid: "user-preview-001",
      reportType: "name",
      status: "pending",
      location: { latitude: 37.5182, longitude: 127.0821 },
      createdAt: dateAt(8),
    },
    {
      id: "preview-closed-request",
      courtId: "osm_node_998877",
      currentName: "성수2가제3동 농구장",
      reason: "공사 펜스로 막혀 있고 코트 시설이 철거되었습니다.",
      requesterName: "서울농구러",
      uid: "user-preview-002",
      reportType: "closed",
      status: "pending",
      location: { latitude: 37.5411, longitude: 127.0671 },
      createdAt: dateAt(54),
    },
    {
      id: "preview-hold-request",
      courtId: "osm_way_445566",
      currentName: "망원1동 농구장",
      reason: "바로 옆 코트와 같은 장소로 중복 등록된 것 같습니다.",
      requesterName: "한강볼러",
      uid: "user-preview-003",
      reportType: "duplicate",
      status: "on_hold",
      location: { latitude: 37.5557, longitude: 126.8975 },
      createdAt: dateAt(520),
    },
    {
      id: "preview-approved-request",
      courtId: "osm_way_778899",
      currentName: "반포2동 농구장",
      requestedName: "반포종합운동장 농구장",
      reason: "정식 시설명을 확인했습니다.",
      requesterName: "코트헌터",
      uid: "user-preview-004",
      reportType: "name",
      status: "approved",
      resolutionNote: "시설 안내판과 공공데이터 명칭 확인",
      createdAt: dateAt(1800),
      reviewedAt: dateAt(1200),
    },
  ];
  state.selectedId = state.reports[0].id;
  state.previewCourtReports = state.reports;
  state.selectedCourt = { name: "잠실2동 농구장", status: "active" };
  hydrateOperator(state.user, state.profile);
  showView("dashboard");
  populateReleaseForm({
    maintenanceEnabled: false,
    maintenanceMessage: "조금 뒤에 다시 접속해주세요.",
    minIosVersion: "1.0.0",
    latestIosVersion: "1.0.0",
    minAndroidVersion: "1.0.0",
    latestAndroidVersion: "1.0.0",
    updateMessage: "최신 버전으로 업데이트해주세요.",
  });
  render();
}

function hydrateOperator(user, profile) {
  const displayName = profile.displayName || user.displayName || "운영자";
  elements.sidebarName.textContent = displayName;
  elements.sidebarRole.textContent = (profile.role || "operator").toUpperCase();
  if (user.photoURL) {
    const image = document.createElement("img");
    image.src = user.photoURL;
    image.alt = "";
    elements.sidebarAvatar.replaceChildren(image);
  } else {
    elements.sidebarAvatar.textContent = initials(displayName);
  }
}

function subscribeToReports() {
  const reportsQuery = query(
    collection(db, state.mode === "court" ? "court_name_requests" : "content_reports"),
    orderBy("createdAt", "desc"),
    limit(200),
  );
  state.unsubscribe = onSnapshot(
    reportsQuery,
    (snapshot) => {
      state.reports = snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
      elements.sync.classList.remove("sync-indicator--error");
      elements.sync.lastChild.textContent = " 실시간 연결";
      if (state.selectedId && !state.reports.some((report) => report.id === state.selectedId)) {
        state.selectedId = null;
        state.selectedCourt = null;
      }
      render();
    },
    (error) => {
      console.error(error);
      elements.sync.classList.add("sync-indicator--error");
      elements.sync.lastChild.textContent = " 연결 오류";
      showToast("제보 목록을 불러오지 못했어요. 권한을 확인해주세요.", true);
    },
  );
}

function subscribeToReleaseConfig() {
  state.unsubscribeConfig = onSnapshot(
    doc(db, "app_config", "release"),
    (snapshot) => {
      populateReleaseForm(snapshot.data() ?? {});
    },
    (error) => {
      console.error(error);
      showToast("앱 운영 설정을 불러오지 못했어요.", true);
    },
  );
}

function populateReleaseForm(config) {
  elements.releaseMaintenance.checked = config.maintenanceEnabled === true;
  elements.releaseMaintenanceMessage.value = config.maintenanceMessage || "조금 뒤에 다시 접속해주세요.";
  elements.releaseMaintenanceEnds.value = dateTimeInputValue(timestampDate(config.maintenanceEndsAt));
  elements.releaseIosMin.value = config.minIosVersion || "1.0.0";
  elements.releaseIosLatest.value = config.latestIosVersion || "1.0.0";
  elements.releaseIosUrl.value = config.iosStoreUrl || "";
  elements.releaseAndroidMin.value = config.minAndroidVersion || "1.0.0";
  elements.releaseAndroidLatest.value = config.latestAndroidVersion || "1.0.0";
  elements.releaseAndroidUrl.value = config.androidStoreUrl || "";
  elements.releaseUpdateMessage.value = config.updateMessage || "최신 버전으로 업데이트해주세요.";
  elements.releaseUpdated.textContent = config.updatedAt
    ? `마지막 저장 · ${dateTimeLabel(timestampDate(config.updatedAt))}`
    : "아직 저장된 설정 없음";
  renderReleaseState();
}

function renderReleaseState() {
  const maintenance = elements.releaseMaintenance.checked;
  elements.releaseStateLabel.textContent = maintenance ? "점검 중" : "정상 운영";
  elements.releaseStateDot.classList.toggle("active", maintenance);
  elements.releaseNavState.textContent = maintenance ? "CHECK" : "LIVE";
  elements.releaseNavState.classList.toggle("soon--danger", maintenance);
}

async function saveReleaseConfig(event) {
  event.preventDefault();
  const versions = [
    elements.releaseIosMin.value,
    elements.releaseIosLatest.value,
    elements.releaseAndroidMin.value,
    elements.releaseAndroidLatest.value,
  ].map((value) => value.trim());
  if (versions.some((value) => value && !/^\d+\.\d+\.\d+$/.test(value))) {
    showToast("버전은 1.0.0 형식으로 입력해주세요.", true);
    return;
  }
  if (elements.releaseMaintenance.checked && !elements.releaseMaintenanceMessage.value.trim()) {
    showToast("점검 안내 문구를 입력해주세요.", true);
    return;
  }

  const endsAt = elements.releaseMaintenanceEnds.value
    ? Timestamp.fromDate(new Date(elements.releaseMaintenanceEnds.value))
    : null;
  const payload = {
    maintenanceEnabled: elements.releaseMaintenance.checked,
    maintenanceMessage: elements.releaseMaintenanceMessage.value.trim(),
    maintenanceEndsAt: endsAt,
    minIosVersion: versions[0],
    latestIosVersion: versions[1],
    iosStoreUrl: elements.releaseIosUrl.value.trim(),
    minAndroidVersion: versions[2],
    latestAndroidVersion: versions[3],
    androidStoreUrl: elements.releaseAndroidUrl.value.trim(),
    updateMessage: elements.releaseUpdateMessage.value.trim() || "최신 버전으로 업데이트해주세요.",
    updatedAt: serverTimestamp(),
    updatedBy: state.user?.uid || "preview",
  };

  elements.releaseSave.disabled = true;
  try {
    if (state.preview) {
      populateReleaseForm({ ...payload, updatedAt: new Date() });
    } else {
      await setDoc(doc(db, "app_config", "release"), payload, { merge: true });
    }
    showToast("앱 운영 설정 저장 완료");
  } catch (error) {
    console.error(error);
    showToast("설정을 저장하지 못했어요.", true);
  } finally {
    elements.releaseSave.disabled = false;
  }
}

function dateTimeInputValue(date) {
  if (!date) return "";
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function switchMode(mode) {
  if (state.mode === mode) return;
  if (state.unsubscribe) state.unsubscribe();
  state.unsubscribe = null;
  state.mode = mode;
  state.reports = [];
  state.selectedId = null;
  state.selectedCourt = null;
  state.filter = "pending";
  state.search = "";
  elements.search.value = "";
  elements.navCourt.classList.toggle("nav__item--active", mode === "court");
  elements.navContent.classList.toggle("nav__item--active", mode === "content");
  elements.navRelease.classList.toggle("nav__item--active", mode === "release");
  elements.reportsStats.classList.toggle("hidden", mode === "release");
  elements.reportsWorkspace.classList.toggle("hidden", mode === "release");
  elements.releaseWorkspace.classList.toggle("hidden", mode !== "release");
  elements.searchControl.classList.toggle("hidden", mode === "release");
  elements.workspaceEyebrow.textContent = mode === "court"
    ? "COURT OPERATIONS"
    : mode === "content" ? "COMMUNITY SAFETY" : "APP CONTROL";
  elements.workspaceTitle.textContent = mode === "court"
    ? "코트 제보"
    : mode === "content" ? "콘텐츠 신고" : "앱 운영";
  if (mode === "release") {
    renderReleaseState();
    return;
  }
  elements.search.placeholder = mode === "court"
    ? "코트명, 제보자, 사유 검색"
    : "신고 사유, 대상 ID 검색";
  document.querySelectorAll(".filter").forEach((button) => {
    button.classList.toggle("active", button.dataset.filter === "pending");
  });
  render();
  if (state.preview) {
    state.reports = mode === "court"
      ? state.previewCourtReports
      : [{
          id: "preview-content-report",
          reporterUid: "user-preview-010",
          targetType: "post",
          targetId: "post-preview-001",
          targetOwnerUid: "user-preview-011",
          reason: "욕설 · 괴롭힘",
          status: "pending",
          createdAt: { toDate: () => new Date(Date.now() - 12 * 60_000) },
        }];
    state.selectedId = state.reports[0]?.id ?? null;
    render();
    return;
  }
  subscribeToReports();
}

function render() {
  renderStats();
  renderList();
  renderDetail();
}

function renderStats() {
  const pending = state.reports.filter((report) => report.status === "pending").length;
  const hold = state.reports.filter((report) => report.status === "on_hold").length;
  const completed = state.reports.filter((report) => ["approved", "rejected"].includes(report.status)).length;
  const today = state.reports.filter((report) => sameLocalDate(timestampDate(report.createdAt), new Date())).length;

  if (state.mode === "court") elements.navPending.textContent = pending;
  if (state.mode === "content") elements.navContentCount.textContent = pending;
  elements.statPending.textContent = pending;
  elements.statHold.textContent = hold;
  elements.statCompleted.textContent = completed;
  elements.statToday.textContent = today;
  elements.filterPending.textContent = pending;
  elements.filterHold.textContent = hold;
  elements.filterCompleted.textContent = completed;
}

function filteredReports() {
  const needle = normalize(state.search);
  return state.reports.filter((report) => {
    const matchesStatus =
      state.filter === "all" ||
      report.status === state.filter ||
      (state.filter === "completed" && ["approved", "rejected"].includes(report.status));
    if (!matchesStatus) return false;
    if (!needle) return true;
    const fields = state.mode === "court"
      ? [report.currentName, report.requestedName, report.requesterName, report.reason, report.courtId]
      : [report.reason, report.targetType, report.targetId, report.targetOwnerUid, report.reporterUid];
    return normalize(fields.filter(Boolean).join(" ")).includes(needle);
  });
}

function renderList() {
  const reports = filteredReports();
  elements.resultCount.textContent = `${reports.length}건`;

  if (!reports.length) {
    elements.reportsList.innerHTML = `
      <div class="list-empty">
        <span>✓</span>
        <h3>${state.search ? "검색 결과가 없어요" : "여기는 깨끗해요"}</h3>
        <p>${state.search ? "다른 검색어로 다시 확인해주세요." : "새로운 제보가 들어오면 실시간으로 표시됩니다."}</p>
      </div>`;
    return;
  }

  elements.reportsList.innerHTML = reports
    .map(state.mode === "court" ? reportRowTemplate : contentReportRowTemplate)
    .join("");
  elements.reportsList.querySelectorAll(".report-row").forEach((row) => {
    row.addEventListener("click", () => selectReport(row.dataset.id));
  });
}

function contentReportRowTemplate(report) {
  const status = statusMeta[report.status] ?? statusMeta.pending;
  const selected = state.selectedId === report.id ? " active" : "";
  const label = report.targetType === "post" ? "게시물" : report.targetType === "comment" ? "댓글" : "사용자";
  return `
    <button class="report-row${selected}" type="button" data-id="${escapeAttribute(report.id)}">
      <span class="type-icon type-icon--closed">!</span>
      <span class="report-row__content">
        <span class="report-row__meta"><span>${label} 신고</span><i></i><span>${relativeTime(timestampDate(report.createdAt))}</span></span>
        <h3>${escapeHtml(report.reason || "신고 사유 없음")}</h3>
        <div class="report-row__change"><span>ID · ${escapeHtml(shortId(report.targetId || "-"))}</span></div>
      </span>
      <span class="status-pill ${status.className}">${status.label}</span>
    </button>`;
}

function reportRowTemplate(report) {
  const type = typeMeta[report.reportType] ?? typeMeta.name;
  const status = statusMeta[report.status] ?? statusMeta.pending;
  const selected = state.selectedId === report.id ? " active" : "";
  const change = report.reportType === "name"
    ? `<div class="report-row__change"><span>${escapeHtml(report.currentName || "농구 코트")}</span><b>→</b><span>${escapeHtml(report.requestedName || "-")}</span></div>`
    : `<div class="report-row__change"><span>${escapeHtml(report.reason || "확인 사유 없음")}</span></div>`;
  return `
    <button class="report-row${selected}" type="button" data-id="${escapeAttribute(report.id)}">
      <span class="type-icon ${type.className}">${type.icon}</span>
      <span class="report-row__content">
        <span class="report-row__meta"><span>${type.label}</span><i></i><span>${relativeTime(timestampDate(report.createdAt))}</span></span>
        <h3>${escapeHtml(report.currentName || "농구 코트")}</h3>
        ${change}
      </span>
      <span class="status-pill ${status.className}">${status.label}</span>
    </button>`;
}

async function selectReport(id) {
  state.selectedId = id;
  state.selectedCourt = undefined;
  renderList();
  renderDetail();
  const report = state.reports.find((item) => item.id === id);
  if (state.mode === "content") {
    state.selectedCourt = null;
    renderDetail();
    return;
  }
  if (state.preview) {
    state.selectedCourt = { name: report?.currentName || "농구 코트", status: "active" };
    renderDetail();
    return;
  }
  if (!report?.courtId) {
    state.selectedCourt = null;
    renderDetail();
    return;
  }
  try {
    const courtSnapshot = await getDoc(doc(db, "courts", report.courtId));
    if (state.selectedId !== id) return;
    state.selectedCourt = courtSnapshot.exists() ? courtSnapshot.data() : null;
  } catch (error) {
    console.error(error);
    state.selectedCourt = null;
  }
  renderDetail();
}

function renderDetail() {
  const report = state.reports.find((item) => item.id === state.selectedId);
  if (!report) {
    elements.reportDetail.innerHTML = `
      <div class="detail-empty">
        <div class="detail-empty__icon">⌁</div>
        <h2>제보를 선택해주세요</h2>
        <p>왼쪽 목록에서 제보를 고르면<br />비교 정보와 처리 버튼이 나타납니다.</p>
      </div>`;
    return;
  }

  if (state.mode === "content") {
    renderContentReportDetail(report);
    return;
  }

  const type = typeMeta[report.reportType] ?? typeMeta.name;
  const status = statusMeta[report.status] ?? statusMeta.pending;
  const created = timestampDate(report.createdAt);
  const currentOfficialName = state.selectedCourt === undefined
    ? "확인 중…"
    : state.selectedCourt?.name || report.currentName || "농구 코트";
  const comparison = comparisonTemplate(report, currentOfficialName);
  const latitude = numberValue(report.location?.latitude ?? state.selectedCourt?.location?.latitude);
  const longitude = numberValue(report.location?.longitude ?? state.selectedCourt?.location?.longitude);
  const hasLocation = Number.isFinite(latitude) && Number.isFinite(longitude);
  const locationLink = hasLocation
    ? `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=18/${latitude}/${longitude}`
    : "";
  const isCompleted = ["approved", "rejected"].includes(report.status);

  elements.reportDetail.innerHTML = `
    <div class="detail-content">
      <header class="detail-head">
        <div class="detail-head__meta">
          <div><span class="status-pill ${status.className}">${status.label}</span><span>${type.label}</span></div>
          <span>${dateTimeLabel(created)}</span>
        </div>
        <h2>${escapeHtml(report.currentName || "농구 코트")}</h2>
        <p>요청 ID · ${escapeHtml(shortId(report.id))}</p>
      </header>

      <div class="detail-body">
        ${comparison}

        <section class="detail-section">
          <h3>제보 사유</h3>
          <p class="reason-box">${escapeHtml(report.reason || "작성된 사유가 없습니다.")}</p>
        </section>

        <section class="detail-section">
          <h3>제보자</h3>
          <div class="requester-card">
            <span class="avatar">${escapeHtml(initials(report.requesterName || "플레이어"))}</span>
            <div><strong>${escapeHtml(report.requesterName || "플레이어")}</strong><span>UID · ${escapeHtml(shortId(report.uid || "-"))}</span></div>
          </div>
        </section>

        <section class="detail-section">
          <h3>코트 위치</h3>
          <div class="location-card">
            <span class="location-pin">⌖</span>
            <div><strong>${hasLocation ? `${latitude.toFixed(6)}, ${longitude.toFixed(6)}` : "위치 정보 없음"}</strong><span>COURT ID · ${escapeHtml(report.courtId || "-")}</span></div>
            ${hasLocation ? `<a href="${locationLink}" target="_blank" rel="noopener noreferrer">지도 보기 ↗</a>` : ""}
          </div>
        </section>

        ${isCompleted ? resolutionTemplate(report) : ""}
      </div>

      ${isCompleted ? "" : `
        <footer class="detail-actions">
          <button class="button button--secondary" type="button" data-decision="on_hold">보류</button>
          <button class="button button--danger" type="button" data-decision="rejected">반려</button>
          <button class="button button--primary" type="button" data-decision="approved">승인 및 반영</button>
        </footer>`}
    </div>`;

  elements.reportDetail.querySelectorAll("[data-decision]").forEach((button) => {
    button.addEventListener("click", () => openDecisionDialog(button.dataset.decision));
  });
}

function renderContentReportDetail(report) {
  const status = statusMeta[report.status] ?? statusMeta.pending;
  const created = timestampDate(report.createdAt);
  const isCompleted = ["approved", "rejected"].includes(report.status);
  const label = report.targetType === "post" ? "게시물" : report.targetType === "comment" ? "댓글" : "사용자";
  elements.reportDetail.innerHTML = `
    <div class="detail-content">
      <header class="detail-head">
        <div class="detail-head__meta">
          <div><span class="status-pill ${status.className}">${status.label}</span><span>${label} 신고</span></div>
          <span>${dateTimeLabel(created)}</span>
        </div>
        <h2>${escapeHtml(report.reason || "신고 사유 없음")}</h2>
        <p>신고 ID · ${escapeHtml(shortId(report.id))}</p>
      </header>
      <div class="detail-body">
        <section class="detail-section">
          <h3>신고 사유</h3>
          <p class="reason-box">${escapeHtml(report.reason || "작성된 사유가 없습니다.")}</p>
        </section>
        <section class="detail-section">
          <h3>대상</h3>
          <div class="location-card">
            <span class="location-pin">!</span>
            <div><strong>${label}</strong><span>TARGET · ${escapeHtml(report.targetId || "-")}</span></div>
          </div>
        </section>
        <section class="detail-section">
          <h3>계정</h3>
          <div class="requester-card">
            <span class="avatar">BC</span>
            <div><strong>신고자 · ${escapeHtml(shortId(report.reporterUid || "-"))}</strong><span>대상 사용자 · ${escapeHtml(shortId(report.targetOwnerUid || "-"))}</span></div>
          </div>
        </section>
        ${isCompleted ? resolutionTemplate(report) : ""}
      </div>
      ${isCompleted ? "" : `
        <footer class="detail-actions">
          <button class="button button--secondary" type="button" data-decision="on_hold">보류</button>
          <button class="button button--secondary" type="button" data-decision="rejected">문제 없음</button>
          <button class="button button--danger" type="button" data-decision="approved">삭제 처리</button>
        </footer>`}
    </div>`;
  elements.reportDetail.querySelectorAll("[data-decision]").forEach((button) => {
    button.addEventListener("click", () => openDecisionDialog(button.dataset.decision));
  });
}

function comparisonTemplate(report, currentOfficialName) {
  if (report.reportType === "new_court") {
    return `
      <section class="detail-section">
        <h3>등록 예정</h3>
        <div class="comparison">
          <div class="comparison-card"><span>현재 데이터</span><strong>미등록</strong></div>
          <div class="comparison-arrow">→</div>
          <div class="comparison-card comparison-card--new"><span>승인 시</span><strong>${escapeHtml(report.requestedName || report.currentName || "-")}</strong></div>
        </div>
      </section>`;
  }
  if (report.reportType === "name") {
    return `
      <section class="detail-section">
        <h3>코트명 비교</h3>
        <div class="comparison">
          <div class="comparison-card"><span>현재 데이터</span><strong>${escapeHtml(currentOfficialName)}</strong></div>
          <div class="comparison-arrow">→</div>
          <div class="comparison-card comparison-card--new"><span>요청 코트명</span><strong>${escapeHtml(report.requestedName || "-")}</strong></div>
        </div>
      </section>`;
  }

  const proposed = report.reportType === "closed" ? "폐쇄 코트로 전환" : "중복 코트로 전환";
  return `
    <section class="detail-section">
      <h3>상태 변경</h3>
      <div class="comparison">
        <div class="comparison-card"><span>현재 데이터</span><strong>${escapeHtml(state.selectedCourt?.status || "active")}</strong></div>
        <div class="comparison-arrow">→</div>
        <div class="comparison-card comparison-card--new"><span>승인 시</span><strong>${proposed}</strong></div>
      </div>
    </section>`;
}

function resolutionTemplate(report) {
  const reviewedAt = timestampDate(report.reviewedAt);
  return `
    <section class="detail-section">
      <h3>처리 결과</h3>
      <div class="resolution-box">
        <strong>${report.status === "approved" ? "승인 완료" : "반려 완료"} · ${dateTimeLabel(reviewedAt)}</strong>
        ${escapeHtml(report.resolutionNote || "별도의 처리 메모가 없습니다.")}
      </div>
    </section>`;
}

function openDecisionDialog(decision) {
  const report = state.reports.find((item) => item.id === state.selectedId);
  if (!report || state.processing) return;
  const labels = state.mode === "content"
    ? {
        approved: { title: "콘텐츠를 삭제할까요?", button: "삭제 처리", description: approvalDescription(report) },
        rejected: { title: "문제없는 신고인가요?", button: "문제 없음", description: "콘텐츠를 유지하고 신고 검토를 끝냅니다." },
        on_hold: { title: "신고를 보류할까요?", button: "보류", description: "추가 확인 뒤 보류 목록에서 다시 처리할 수 있습니다." },
      }
    : {
        approved: { title: "제보를 승인할까요?", button: "승인 및 반영", description: approvalDescription(report) },
        rejected: { title: "제보를 반려할까요?", button: "반려하기", description: "제보는 처리 완료로 이동하고 코트 데이터는 변경되지 않습니다." },
        on_hold: { title: "제보를 보류할까요?", button: "보류로 이동", description: "추가 확인이 끝난 뒤 보류 목록에서 다시 처리할 수 있습니다." },
      };
  const copy = labels[decision];
  elements.decisionForm.dataset.decision = decision;
  elements.dialogTitle.textContent = copy.title;
  elements.dialogDescription.textContent = copy.description;
  elements.dialogSubmit.textContent = copy.button;
  elements.dialogSubmit.className = decision === "rejected" ? "button button--danger" : "button button--primary";
  elements.note.value = "";
  elements.noteCount.textContent = "0";
  elements.dialog.showModal();
  window.setTimeout(() => elements.note.focus(), 80);
}

function approvalDescription(report) {
  if (state.mode === "content") return "신고된 콘텐츠가 삭제되고 신고가 처리 완료됩니다.";
  if (report.reportType === "name") return `코트명이 “${report.requestedName || "-"}”(으)로 즉시 변경됩니다.`;
  if (report.reportType === "new_court") return "제보된 위치에 새 코트가 즉시 등록됩니다.";
  if (report.reportType === "closed") return "해당 코트가 폐쇄 상태로 전환됩니다.";
  return "해당 코트가 중복 상태로 전환됩니다.";
}

async function submitDecision(event) {
  event.preventDefault();
  const report = state.reports.find((item) => item.id === state.selectedId);
  const decision = elements.decisionForm.dataset.decision;
  if (!report || !["approved", "rejected", "on_hold"].includes(decision) || state.processing) return;

  state.processing = true;
  elements.dialogSubmit.disabled = true;
  try {
    await reviewReport(report, decision, elements.note.value.trim());
    elements.dialog.close();
    const message = state.mode === "content"
      ? decision === "approved" ? "신고된 콘텐츠를 삭제했어요." : decision === "rejected" ? "문제없는 신고로 처리했어요." : "신고를 보류했어요."
      : decision === "approved" ? "승인 내용이 코트 데이터에 반영됐어요." : decision === "rejected" ? "제보를 반려했어요." : "제보를 보류 목록으로 옮겼어요.";
    showToast(message);
  } catch (error) {
    console.error(error);
    showToast(error?.message || "제보를 처리하지 못했어요.", true);
  } finally {
    state.processing = false;
    elements.dialogSubmit.disabled = false;
  }
}

async function reviewReport(report, decision, resolutionNote) {
  if (state.preview) {
    report.status = decision;
    report.resolutionNote = resolutionNote;
    report.reviewedAt = { toDate: () => new Date() };
    render();
    return;
  }
  if (!state.user) throw new Error("로그인이 필요합니다.");
  if (state.mode === "content") {
    await reviewContentReport(report, decision, resolutionNote);
    return;
  }
  const requestRef = doc(db, "court_name_requests", report.id);
  const courtRef = doc(db, "courts", report.courtId);

  await runTransaction(db, async (transaction) => {
    const requestSnapshot = await transaction.get(requestRef);
    if (!requestSnapshot.exists()) throw new Error("이미 삭제된 제보예요.");
    const request = requestSnapshot.data();
    if (["approved", "rejected"].includes(request.status)) throw new Error("이미 처리가 끝난 제보예요.");

    transaction.update(requestRef, {
      status: decision,
      resolutionNote,
      reviewedBy: state.user.uid,
      reviewedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    if (request.uid && request.uid !== state.user.uid) {
      transaction.set(doc(collection(db, "notification_events")), {
        actorUid: state.user.uid,
        type: "court_report",
        title: "코트 제보 처리",
        body: decision === "approved" ? "제보한 내용이 반영됐어요." : decision === "on_hold" ? "제보한 내용을 확인 중이에요." : "제보한 내용이 반려됐어요.",
        courtId: request.courtId || null,
        entityId: report.id,
        createdAt: serverTimestamp(),
        status: "pending",
      });
    }

    if (decision !== "approved") return;
    const courtUpdate = {
      updatedAt: serverTimestamp(),
      statusUpdatedAt: serverTimestamp(),
      statusUpdatedBy: state.user.uid,
    };

    if (request.reportType === "new_court") {
      const requestedName = String(request.requestedName || request.currentName || "").trim();
      const location = request.location;
      if (requestedName.length < 2 || !location) throw new Error("새 코트 정보가 완전하지 않아요.");
      transaction.set(courtRef, {
        name: requestedName,
        location,
        source: "user_report",
        nameSource: "operator",
        status: "active",
        createdByReportId: report.id,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      return;
    }
    if (request.reportType === "name") {
      const requestedName = String(request.requestedName || "").trim();
      if (requestedName.length < 2) throw new Error("변경할 코트명이 올바르지 않아요.");
      Object.assign(courtUpdate, {
        name: requestedName,
        nameSource: "operator",
        nameUpdatedAt: serverTimestamp(),
        nameUpdatedBy: state.user.uid,
      });
    } else if (request.reportType === "duplicate" || request.reportType === "closed") {
      Object.assign(courtUpdate, {
        status: request.reportType,
        statusReason: resolutionNote || request.reason || "",
      });
    } else {
      throw new Error("지원하지 않는 제보 유형이에요.");
    }
    transaction.update(courtRef, courtUpdate);
  });
}

async function reviewContentReport(report, decision, resolutionNote) {
  const reportRef = doc(db, "content_reports", report.id);
  await runTransaction(db, async (transaction) => {
    const snapshot = await transaction.get(reportRef);
    if (!snapshot.exists()) throw new Error("이미 삭제된 신고예요.");
    const current = snapshot.data();
    if (["approved", "rejected"].includes(current.status)) throw new Error("이미 처리가 끝난 신고예요.");
    transaction.update(reportRef, {
      status: decision,
      resolutionNote,
      reviewedBy: state.user.uid,
      reviewedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    if (current.reporterUid && current.reporterUid !== state.user.uid) {
      transaction.set(doc(collection(db, "notification_events")), {
        actorUid: state.user.uid,
        type: "court_report",
        title: "신고 처리",
        body: decision === "approved" ? "신고한 콘텐츠가 처리됐어요." : decision === "on_hold" ? "신고 내용을 확인 중이에요." : "신고 검토가 끝났어요.",
        courtId: null,
        entityId: report.id,
        createdAt: serverTimestamp(),
        status: "pending",
      });
    }
    if (decision === "approved" && current.targetType === "post") {
      transaction.delete(doc(db, "posts", current.targetId));
    }
    if (decision === "approved" && current.targetType === "comment") {
      transaction.delete(doc(db, "comments", current.targetId));
    }
  });
}

let toastTimer;
function showToast(message, isError = false) {
  window.clearTimeout(toastTimer);
  elements.toast.textContent = message;
  elements.toast.classList.toggle("error", isError);
  elements.toast.classList.add("show");
  toastTimer = window.setTimeout(() => elements.toast.classList.remove("show"), 2800);
}

function timestampDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function relativeTime(date) {
  if (!date) return "방금 전";
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));
  if (seconds < 60) return "방금 전";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}분 전`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}시간 전`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}일 전`;
  return new Intl.DateTimeFormat("ko-KR", { month: "short", day: "numeric" }).format(date);
}

function dateTimeLabel(date) {
  if (!date) return "시간 정보 없음";
  return new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function sameLocalDate(a, b) {
  return Boolean(a) && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function numberValue(value) {
  return typeof value === "number" ? value : Number(value);
}

function shortId(value) {
  const text = String(value || "-");
  return text.length <= 12 ? text : `${text.slice(0, 6)}…${text.slice(-4)}`;
}

function initials(name) {
  const cleaned = String(name || "BC").trim();
  return cleaned.slice(0, 2).toUpperCase();
}

function normalize(value) {
  return String(value || "").trim().toLocaleLowerCase("ko-KR").replace(/\s+/g, " ");
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[character]);
}

function escapeAttribute(value) {
  return escapeHtml(value).replace(/`/g, "&#96;");
}

elements.googleLogin.addEventListener("click", loginWithGoogle);
elements.emailForm.addEventListener("submit", loginWithEmail);
elements.logout.addEventListener("click", logout);
elements.deniedLogout.addEventListener("click", logout);
elements.navCourt.addEventListener("click", () => switchMode("court"));
elements.navContent.addEventListener("click", () => switchMode("content"));
elements.navRelease.addEventListener("click", () => switchMode("release"));
elements.releaseMaintenance.addEventListener("change", renderReleaseState);
elements.releaseForm.addEventListener("submit", saveReleaseConfig);
elements.search.addEventListener("input", (event) => {
  state.search = event.target.value;
  renderList();
});

document.querySelectorAll(".filter").forEach((button) => {
  button.addEventListener("click", () => {
    state.filter = button.dataset.filter;
    document.querySelectorAll(".filter").forEach((item) => item.classList.toggle("active", item === button));
    renderList();
  });
});

document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    elements.search.focus();
  }
  if (event.key === "Escape" && elements.dialog.open) elements.dialog.close();
});

elements.dialogClose.addEventListener("click", () => elements.dialog.close());
elements.dialogCancel.addEventListener("click", () => elements.dialog.close());
elements.note.addEventListener("input", () => { elements.noteCount.textContent = elements.note.value.length; });
elements.decisionForm.addEventListener("submit", submitDecision);
elements.dialog.addEventListener("click", (event) => {
  if (event.target === elements.dialog) elements.dialog.close();
});

const localPreview = ["localhost", "127.0.0.1"].includes(window.location.hostname)
  && new URLSearchParams(window.location.search).has("preview");
if (localPreview) {
  startLocalPreview();
  if (new URLSearchParams(window.location.search).get("preview") === "release") {
    switchMode("release");
  }
} else {
  onAuthStateChanged(auth, handleAuthState);
}
