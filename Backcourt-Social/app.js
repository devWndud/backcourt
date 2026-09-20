const SIZE = 1080;
const C = {
  ink: "#070707",
  panel: "#151515",
  orange: "#ff5d3b",
  paper: "#f1efe8",
  white: "#ffffff",
  muted: "#929292",
};

const sources = {
  icon: "./assets/app-icon.png",
  ball: "./assets/ball.png",
  map: "./assets/map.png",
  live: "./assets/live.png",
  meetup: "./assets/meetup.png",
  checkin: "./assets/checkin.png",
  feed: "./assets/feed.png",
  profile: "./assets/profile.png",
};

const images = {};
const exportSlide = Number(new URLSearchParams(window.location.search).get("export"));

if (exportSlide >= 1 && exportSlide <= 5) {
  document.body.classList.add("export-mode");
  document.querySelectorAll(".creative")[exportSlide - 1].classList.add("is-export");
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = src;
  });
}

function font(weight, size) {
  return `${weight} ${size}px "Apple SD Gothic Neo", "Noto Sans KR", sans-serif`;
}

function roundedPath(ctx, x, y, width, height, radius) {
  const r = Math.min(radius, width / 2, height / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + width, y, x + width, y + height, r);
  ctx.arcTo(x + width, y + height, x, y + height, r);
  ctx.arcTo(x, y + height, x, y, r);
  ctx.arcTo(x, y, x + width, y, r);
  ctx.closePath();
}

function roundedFill(ctx, x, y, width, height, radius, color) {
  ctx.save();
  roundedPath(ctx, x, y, width, height, radius);
  ctx.fillStyle = color;
  ctx.fill();
  ctx.restore();
}

function coverImage(ctx, image, x, y, width, height, radius = 0, anchorY = .5) {
  const scale = Math.max(width / image.width, height / image.height);
  const sourceWidth = width / scale;
  const sourceHeight = height / scale;
  const sourceX = (image.width - sourceWidth) / 2;
  const sourceY = Math.max(0, Math.min(image.height - sourceHeight, (image.height - sourceHeight) * anchorY));
  ctx.save();
  if (radius) {
    roundedPath(ctx, x, y, width, height, radius);
    ctx.clip();
  }
  ctx.drawImage(image, sourceX, sourceY, sourceWidth, sourceHeight, x, y, width, height);
  ctx.restore();
}

function phone(ctx, image, x, y, width, height, angle = 0, anchorY = .5) {
  ctx.save();
  ctx.translate(x + width / 2, y + height / 2);
  ctx.rotate(angle * Math.PI / 180);
  ctx.translate(-width / 2, -height / 2);
  ctx.shadowColor = "rgba(0,0,0,.32)";
  ctx.shadowBlur = 42;
  ctx.shadowOffsetY = 24;
  roundedFill(ctx, 0, 0, width, height, 48, "#050505");
  ctx.shadowColor = "transparent";
  coverImage(ctx, image, 10, 10, width - 20, height - 20, 40, anchorY);
  ctx.strokeStyle = "rgba(255,255,255,.14)";
  ctx.lineWidth = 2;
  roundedPath(ctx, 0, 0, width, height, 48);
  ctx.stroke();
  ctx.restore();
}

function label(ctx, text, x, y, color = C.orange) {
  ctx.fillStyle = color;
  ctx.font = font(900, 25);
  ctx.fillText(text, x, y);
}

function brand(ctx, dark = false) {
  roundedFill(ctx, 58, 52, 58, 58, 8, C.ink);
  ctx.drawImage(images.icon, 58, 52, 58, 58);
  ctx.fillStyle = dark ? C.white : C.ink;
  ctx.font = font(900, 29);
  ctx.fillText("빽코트", 132, 91);
}

function courtLines(ctx, color, alpha = .22) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.globalAlpha = alpha;
  ctx.lineWidth = 4;
  ctx.beginPath();
  ctx.arc(0, 1080, 340, Math.PI * 1.5, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(1080, 1080, 210, Math.PI, Math.PI * 1.5);
  ctx.stroke();
  ctx.restore();
}

function slide1(ctx) {
  ctx.fillStyle = C.paper;
  ctx.fillRect(0, 0, SIZE, SIZE);
  brand(ctx, false);
  label(ctx, "BACKCOURT", 72, 252);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 110);
  ctx.fillText("일상에서", 70, 380);
  ctx.fillStyle = C.orange;
  ctx.fillText("다시, 코트로.", 70, 508);
  ctx.fillStyle = C.ink;
  ctx.fillRect(72, 575, 68, 10);
  ctx.font = font(800, 30);
  ctx.fillText("코트 · LIVE · 약속 · 출석", 72, 646);

  ctx.save();
  ctx.globalAlpha = .065;
  ctx.filter = "brightness(0)";
  ctx.drawImage(images.ball, 724, 92, 330, 330);
  ctx.restore();

  ctx.fillStyle = C.orange;
  ctx.fillRect(0, 760, SIZE, 320);
  courtLines(ctx, C.ink, .18);
  ctx.save();
  ctx.translate(758, 770);
  ctx.rotate(-4 * Math.PI / 180);
  ctx.shadowColor = "rgba(0,0,0,.22)";
  ctx.shadowBlur = 24;
  ctx.shadowOffsetY = 18;
  ctx.drawImage(images.icon, 0, 0, 258, 258);
  ctx.restore();
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 22);
  ctx.fillText("FIND YOUR COURT", 72, 932);
  ctx.font = font(900, 18);
  ctx.fillText("IOS / ANDROID", 72, 976);
}

function slide2(ctx) {
  ctx.fillStyle = C.ink;
  ctx.fillRect(0, 0, SIZE, SIZE);
  brand(ctx, true);
  label(ctx, "COURT MAP", 72, 216);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 92);
  ctx.fillText("전국 농구", 70, 328);
  ctx.fillText("코트 지도", 70, 432);
  roundedFill(ctx, 70, 493, 360, 72, 36, C.orange);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 28);
  ctx.fillText("전국 코트 30,577곳", 100, 540);
  ctx.fillStyle = C.muted;
  ctx.font = font(700, 25);
  ctx.fillText("야외  /  무료  /  조명", 72, 622);

  ctx.save();
  ctx.globalAlpha = .055;
  ctx.drawImage(images.ball, -145, 700, 470, 470);
  ctx.restore();
  phone(ctx, images.map, 612, 116, 390, 846, 2, .42);
  ctx.fillStyle = C.orange;
  ctx.beginPath();
  ctx.arc(585, 798, 18, 0, Math.PI * 2);
  ctx.fill();
}

function slide3(ctx) {
  ctx.fillStyle = C.orange;
  ctx.fillRect(0, 0, SIZE, SIZE);
  brand(ctx, false);
  label(ctx, "PLAY TOGETHER", 72, 200, C.ink);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 92);
  ctx.fillText("실시간 LIVE", 70, 306);
  ctx.fillText("농구 약속", 70, 408);

  roundedFill(ctx, 728, 196, 282, 74, 37, C.ink);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 25);
  ctx.fillText("LIVE  /  약속", 774, 244);

  phone(ctx, images.live, 112, 470, 390, 846, -4, .24);
  phone(ctx, images.meetup, 574, 402, 390, 846, 4, .25);
}

function slide4(ctx) {
  ctx.fillStyle = C.paper;
  ctx.fillRect(0, 0, SIZE, SIZE);
  brand(ctx, false);
  label(ctx, "COURT CHECK-IN", 70, 214);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 86);
  ctx.fillText("GPS 출석", 68, 320);
  ctx.fillStyle = C.orange;
  ctx.fillText("코트 랭킹", 68, 418);
  ctx.fillStyle = "#55524e";
  ctx.font = font(800, 26);
  ctx.fillText("GPS 출석 · 플레이 시간 · 월간 랭킹", 72, 480);

  roundedFill(ctx, 66, 596, 440, 284, 38, C.ink);
  label(ctx, "COURT RANKING", 100, 652);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 52);
  ctx.fillText("이번 달 1위", 98, 724);
  ctx.fillStyle = C.orange;
  ctx.font = font(900, 72);
  ctx.fillText("COURT #1", 98, 817);

  ctx.save();
  ctx.globalAlpha = .06;
  ctx.filter = "brightness(0)";
  ctx.drawImage(images.ball, -110, 742, 420, 420);
  ctx.restore();
  phone(ctx, images.checkin, 620, 124, 390, 846, 2, .42);
}

function slide5(ctx) {
  ctx.fillStyle = C.ink;
  ctx.fillRect(0, 0, SIZE, SIZE);
  brand(ctx, true);
  label(ctx, "COURT STORIES", 70, 205);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 86);
  ctx.fillText("코트 리뷰", 68, 308);
  ctx.fillStyle = C.orange;
  ctx.fillText("농구 피드", 68, 408);
  ctx.fillStyle = C.muted;
  ctx.font = font(800, 26);
  ctx.fillText("피드 · 프로필 · 나의 기록", 72, 468);

  phone(ctx, images.feed, 82, 548, 380, 824, -4, .15);
  phone(ctx, images.profile, 602, 474, 380, 824, 4, .14);

  ctx.save();
  ctx.globalAlpha = .06;
  ctx.drawImage(images.ball, 420, 28, 600, 600);
  ctx.restore();
}

const renderers = [slide1, slide2, slide3, slide4, slide5];

function renderAll() {
  renderers.forEach((render, index) => {
    const canvas = document.querySelector(`#slide-${index + 1}`);
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, SIZE, SIZE);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    render(ctx);
  });
}

function downloadSlide(number) {
  const canvas = document.querySelector(`#slide-${number}`);
  const link = document.createElement("a");
  link.download = `backcourt-instagram-${String(number).padStart(2, "0")}.png`;
  link.href = canvas.toDataURL("image/png", 1);
  link.click();
}

document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-slide]");
  if (button) downloadSlide(Number(button.dataset.slide));
});

document.querySelector("#download-all").addEventListener("click", () => {
  for (let number = 1; number <= 5; number += 1) {
    setTimeout(() => downloadSlide(number), (number - 1) * 180);
  }
});

Promise.all(Object.entries(sources).map(async ([key, src]) => {
  images[key] = await loadImage(src);
})).then(() => document.fonts.ready).then(renderAll).catch((error) => {
  console.error(error);
  document.body.dataset.error = "true";
});
