const SIZE = 1080;
const C = {
  ink: "#070707",
  panel: "#151515",
  orange: "#ff612d",
  orangeDeep: "#db4d24",
  paper: "#f1efe8",
  white: "#ffffff",
  muted: "#929292",
};

const sources = {
  icon: "./assets/app-icon.png",
  markLight: "./assets/brand-mark-on-light.png",
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
  ctx.font = font(900, 24);
  ctx.fillText(text, x, y);
}

function trackedText(ctx, text, x, y, tracking = 5) {
  let cursor = x;
  for (const character of text) {
    ctx.fillText(character, cursor, y);
    cursor += ctx.measureText(character).width + tracking;
  }
}

function brand(ctx, mode = "light") {
  const dark = mode === "dark";
  const compact = mode === "compact";
  const size = compact ? 54 : 66;
  const x = compact ? 54 : 58;
  const y = compact ? 50 : 48;
  ctx.drawImage(dark ? images.icon : images.markLight, x, y, size, size);
  ctx.fillStyle = dark ? C.white : C.ink;
  ctx.font = font(900, compact ? 25 : 28);
  ctx.fillText("빽코트", x + size + 15, y + size * .67);
}

function slideMeta(ctx, index, color = C.ink) {
  ctx.save();
  ctx.fillStyle = color;
  ctx.font = font(900, 17);
  trackedText(ctx, `${String(index).padStart(2, "0")} / 05`, 913, 73, 2.5);
  ctx.restore();
}

function platformMeta(ctx, color = C.ink) {
  ctx.save();
  ctx.fillStyle = color;
  ctx.font = font(900, 17);
  trackedText(ctx, "IOS / ANDROID", 818, 72, 3);
  ctx.restore();
}

function giantType(ctx, lines, x, y, size, lineHeight, color, alpha = 1) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.fillStyle = color;
  ctx.font = `950 ${size}px Arial, "Apple SD Gothic Neo", sans-serif`;
  ctx.textBaseline = "top";
  lines.forEach((line, index) => ctx.fillText(line, x, y + index * lineHeight));
  ctx.restore();
}

function footerTag(ctx, text, color = C.ink) {
  ctx.fillStyle = color;
  ctx.fillRect(54, 998, 72, 6);
  ctx.font = font(900, 19);
  trackedText(ctx, text, 150, 1007, 3);
}

function heroIcon(ctx, x, y, size, angle = -3) {
  ctx.save();
  ctx.translate(x + size / 2, y + size / 2);
  ctx.rotate(angle * Math.PI / 180);
  ctx.translate(-size / 2, -size / 2);
  ctx.shadowColor = "rgba(0,0,0,.18)";
  ctx.shadowBlur = 0;
  ctx.shadowOffsetX = 26;
  ctx.shadowOffsetY = 30;
  ctx.drawImage(images.icon, 0, 0, size, size);
  ctx.restore();
}

function courtLines(ctx, color, alpha = .22) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.globalAlpha = alpha;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.arc(0, 1080, 370, Math.PI * 1.5, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(1080, 1080, 228, Math.PI, Math.PI * 1.5);
  ctx.stroke();
  ctx.restore();
}

function slide1(ctx) {
  ctx.fillStyle = C.orange;
  ctx.fillRect(0, 0, SIZE, SIZE);
  giantType(ctx, ["BACK", "COURT"], 222, 64, 286, 244, C.ink, .12);
  platformMeta(ctx);
  heroIcon(ctx, 226, 332, 628);
  courtLines(ctx, C.ink, .18);
  footerTag(ctx, "FIND YOUR COURT");
}

function slide2(ctx) {
  ctx.fillStyle = C.paper;
  ctx.fillRect(0, 0, SIZE, SIZE);
  giantType(ctx, ["COURT", "MAP"], -24, -72, 282, 238, C.ink, .045);
  brand(ctx, "compact");
  slideMeta(ctx, 2);
  label(ctx, "COURT MAP", 62, 236);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 99);
  ctx.fillText("코트 찾기", 58, 342);
  ctx.fillStyle = C.orange;
  ctx.font = font(900, 76);
  ctx.fillText("30,577", 59, 444);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 26);
  trackedText(ctx, "COURTS", 64, 488, 3);
  ctx.fillRect(62, 542, 58, 8);
  ctx.font = font(800, 24);
  ctx.fillText("야외  ·  무료  ·  조명", 62, 606);
  ctx.save();
  ctx.globalAlpha = .045;
  ctx.filter = "brightness(0)";
  ctx.drawImage(images.ball, -268, 616, 660, 660);
  ctx.restore();
  phone(ctx, images.map, 570, 158, 440, 952, 2.5, .40);
  ctx.fillStyle = C.orange;
  ctx.fillRect(524, 729, 78, 78);
  ctx.fillStyle = C.white;
  ctx.beginPath();
  ctx.arc(563, 768, 12, 0, Math.PI * 2);
  ctx.fill();
  footerTag(ctx, "FIND A COURT");
}

function slide3(ctx) {
  ctx.fillStyle = C.orange;
  ctx.fillRect(0, 0, SIZE, SIZE);
  giantType(ctx, ["LIVE", "GAME"], 92, -70, 310, 248, C.ink, .12);
  brand(ctx, "compact");
  slideMeta(ctx, 3);
  label(ctx, "LIVE / MEETUP", 62, 216, C.ink);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 86);
  ctx.fillText("지금 코트", 60, 316);
  roundedFill(ctx, 732, 218, 274, 68, 34, C.ink);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 24);
  ctx.fillText("LIVE   /   약속", 773, 261);
  phone(ctx, images.live, 70, 414, 408, 884, -4, .23);
  phone(ctx, images.meetup, 604, 372, 408, 884, 4, .24);
}

function slide4(ctx) {
  ctx.fillStyle = C.ink;
  ctx.fillRect(0, 0, SIZE, SIZE);
  giantType(ctx, ["CHECK", "IN"], -34, -84, 278, 232, C.orange, .14);
  brand(ctx, "dark");
  slideMeta(ctx, 4, C.white);
  label(ctx, "GPS CHECK-IN", 62, 226);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 94);
  ctx.fillText("출석", 60, 336);
  ctx.fillStyle = C.orange;
  ctx.fillText("랭킹", 60, 442);
  roundedFill(ctx, 58, 532, 400, 264, 0, C.orange);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 20);
  trackedText(ctx, "THIS MONTH", 91, 582, 2.5);
  ctx.font = font(900, 118);
  ctx.fillText("01", 86, 706);
  ctx.font = font(900, 24);
  ctx.fillText("COURT RANK", 245, 691);
  phone(ctx, images.checkin, 578, 130, 436, 944, 2, .41);
  footerTag(ctx, "LEAVE YOUR MARK", C.white);
}

function slide5(ctx) {
  ctx.fillStyle = C.paper;
  ctx.fillRect(0, 0, SIZE, SIZE);
  giantType(ctx, ["YOUR", "COURT"], 116, -76, 274, 232, C.ink, .045);
  brand(ctx, "compact");
  slideMeta(ctx, 5);
  label(ctx, "FEED / PROFILE", 62, 214);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 84);
  ctx.fillText("피드", 60, 316);
  ctx.fillStyle = C.orange;
  ctx.fillText("프로필", 60, 414);
  phone(ctx, images.feed, 64, 484, 398, 862, -4, .14);
  phone(ctx, images.profile, 618, 430, 398, 862, 4, .14);
  roundedFill(ctx, 390, 889, 300, 74, 37, C.orange);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 23);
  ctx.textAlign = "center";
  ctx.fillText("일상에서, 다시 코트로.", 540, 935);
  ctx.textAlign = "left";
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
