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
};

const images = {};
const exportSlide = Number(new URLSearchParams(window.location.search).get("export"));

if (exportSlide === 1) {
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
  trackedText(ctx, "IOS / ANDROID", 856, 46, 3);
  ctx.restore();
}

function giantType(ctx, lines, x, y, size, lineHeight, color, alpha = 1, align = "left") {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.fillStyle = color;
  ctx.font = `950 ${size}px Arial, "Apple SD Gothic Neo", sans-serif`;
  ctx.textBaseline = "top";
  ctx.textAlign = align;
  lines.forEach((line, index) => ctx.fillText(line, x, y + index * lineHeight));
  ctx.restore();
}

function storeMarks(ctx, x, y) {
  ctx.save();
  ctx.fillStyle = C.white;
  const play = new Path2D("M3.7 2.4 14 12 3.7 21.6A2.6 2.6 0 0 1 3 19.8V4.2c0-.7.3-1.3.7-1.8Zm11.6 10.8 2.7 2.5L6.2 22.2l9.1-9Zm3.9-3.6c.6.3 1 .9 1 1.5s-.4 1.2-1 1.5l-2 1.1-2.9-2.7 2.9-2.7 2 1.3ZM6.2 1.8 18 8.3l-2.7 2.5-9.1-9Z");
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(1.65, 1.65);
  ctx.fill(play);
  ctx.restore();

  const apple = new Path2D("M16.8 12.8c0-2.6 2.1-3.8 2.2-3.9a4.7 4.7 0 0 0-3.7-2c-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.3-.8A4.9 4.9 0 0 0 4 9.5c-1.8 3-.5 7.5 1.2 10 .8 1.2 1.8 2.5 3.1 2.4 1.2-.1 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.2 3-2.4a10.7 10.7 0 0 0 1.4-2.9 4.4 4.4 0 0 1-2.3-3.8ZM14.3 5.3A4.5 4.5 0 0 0 15.4 2a4.6 4.6 0 0 0-3 1.6 4.2 4.2 0 0 0-1.1 3.2 3.8 3.8 0 0 0 3-1.5Z");
  ctx.save();
  ctx.translate(x + 56, y);
  ctx.scale(1.65, 1.65);
  ctx.fill(apple);
  ctx.restore();
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

function mapArtwork(ctx, x, y, width, height) {
  ctx.save();
  ctx.beginPath();
  ctx.rect(x, y, width, height);
  ctx.clip();
  ctx.fillStyle = C.ink;
  ctx.fillRect(x, y, width, height);

  ctx.strokeStyle = "#262626";
  ctx.lineWidth = 3;
  const roads = [
    [-80, 120, 680, 560], [40, -40, 610, 410], [-120, 430, 720, 690],
    [90, 860, 650, 180], [240, -70, 120, 1040], [500, -40, 260, 1030],
    [-50, 740, 700, 470], [0, 260, 680, 70], [120, 980, 580, 610],
  ];
  roads.forEach(([x1, y1, x2, y2]) => {
    ctx.beginPath();
    ctx.moveTo(x + x1, y + y1);
    ctx.lineTo(x + x2, y + y2);
    ctx.stroke();
  });

  ctx.strokeStyle = "#171717";
  ctx.lineWidth = 1;
  for (let row = 0; row < 10; row += 1) {
    ctx.strokeRect(x + 34 + (row % 2) * 24, y + 70 + row * 86, width - 90, 48);
  }

  const markers = [[.37, .38, 11], [.45, .46, 11], [.43, .48, 11], [.49, .54, 11], [.72, .73, 11]];
  markers.forEach(([px, py, radius]) => {
    ctx.fillStyle = "rgba(255,97,45,.20)";
    ctx.beginPath();
    ctx.arc(x + width * px, y + height * py, radius * 2.3, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = C.orange;
    ctx.strokeStyle = C.white;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(x + width * px, y + height * py, radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
  });

  ctx.fillStyle = C.orange;
  ctx.fillRect(x + 42, y + height - 105, 220, 58);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 19);
  ctx.fillText("30,577 COURTS", x + 68, y + height - 69);
  ctx.restore();
}

function liveCard(ctx, x, y, width, height, type) {
  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,.18)";
  ctx.shadowBlur = 0;
  ctx.shadowOffsetX = 18;
  ctx.shadowOffsetY = 22;
  roundedFill(ctx, x, y, width, height, 42, C.ink);
  ctx.shadowColor = "transparent";
  ctx.fillStyle = C.orange;
  ctx.font = font(900, 20);
  trackedText(ctx, type === "live" ? "LIVE" : "MEETUP", x + 38, y + 58, 3);
  ctx.fillStyle = C.white;

  if (type === "live") {
    ctx.font = font(900, 148);
    ctx.fillText("05", x + 34, y + 213);
    ctx.font = font(900, 27);
    ctx.fillText("PLAYING", x + 42, y + 260);
    ctx.fillStyle = C.orange;
    ctx.fillRect(x + 34, y + 315, width - 68, 176);
    ctx.fillStyle = C.ink;
    ctx.font = font(900, 24);
    ctx.fillText("지금 코트", x + 62, y + 365);
    ctx.font = font(900, 48);
    ctx.fillText("영등포덩크", x + 61, y + 428);
  } else {
    ctx.font = font(900, 104);
    ctx.fillText("19:30", x + 36, y + 190);
    ctx.fillStyle = C.orange;
    ctx.font = font(900, 25);
    ctx.fillText("오늘", x + 42, y + 252);
    ctx.fillStyle = C.white;
    ctx.font = font(900, 38);
    ctx.fillText("4 / 6", x + 42, y + 318);
    ctx.strokeStyle = C.orange;
    ctx.lineWidth = 8;
    ctx.beginPath();
    ctx.moveTo(x + 42, y + 376);
    ctx.lineTo(x + width - 42, y + 376);
    ctx.stroke();
    ctx.fillStyle = C.muted;
    ctx.font = font(800, 22);
    ctx.fillText("한강 시민공원", x + 42, y + 432);
  }
  ctx.restore();
}

function radarArtwork(ctx, centerX, centerY) {
  ctx.save();
  ctx.strokeStyle = "rgba(255,255,255,.20)";
  ctx.lineWidth = 3;
  [72, 116, 160, 204].forEach((radius) => {
    ctx.beginPath();
    ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
    ctx.stroke();
  });
  ctx.fillStyle = C.white;
  ctx.beginPath();
  ctx.arc(centerX, centerY, 66, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = C.ink;
  ctx.beginPath();
  ctx.moveTo(centerX + 28, centerY - 34);
  ctx.lineTo(centerX + 5, centerY + 33);
  ctx.lineTo(centerX - 13, centerY + 8);
  ctx.lineTo(centerX - 40, centerY - 5);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

function feedArtwork(ctx, x, y, width, height) {
  ctx.fillStyle = C.ink;
  ctx.fillRect(x, y, width, height);
  const blocks = [
    [24, 24, width - 48, 150], [24, 194, width * .45, 220],
    [width * .51, 194, width * .43, 220], [24, 434, width - 48, 190],
  ];
  blocks.forEach(([bx, by, bw, bh], index) => {
    ctx.fillStyle = index === 2 ? C.orange : "#1d1d1d";
    ctx.fillRect(x + bx, y + by, bw, bh);
    ctx.strokeStyle = index === 2 ? C.ink : "#3a3a3a";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(x + bx + bw * .5, y + by + bh * .5, Math.min(bw, bh) * .28, 0, Math.PI * 2);
    ctx.stroke();
  });
}

function profileArtwork(ctx, x, y, width, height) {
  ctx.fillStyle = C.ink;
  ctx.fillRect(x, y, width, height);
  ctx.drawImage(images.icon, x + 38, y + 42, 116, 116);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 36);
  ctx.fillText("BACKCOURT", x + 180, y + 90);
  ctx.fillStyle = C.orange;
  ctx.font = font(900, 19);
  ctx.fillText("@BACKCOURT", x + 182, y + 126);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 54);
  ctx.fillText("24", x + 42, y + 252);
  ctx.fillText("18", x + 172, y + 252);
  ctx.fillText("07", x + 302, y + 252);
  ctx.fillStyle = C.muted;
  ctx.font = font(800, 18);
  ctx.fillText("POST", x + 45, y + 286);
  ctx.fillText("CHECK-IN", x + 166, y + 286);
  ctx.fillText("LIVE", x + 312, y + 286);
  ctx.fillStyle = C.paper;
  ctx.fillRect(x + 38, y + 346, width - 76, 190);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 19);
  trackedText(ctx, "COURT RECORD", x + 62, y + 390, 2);
  ctx.font = font(900, 54);
  ctx.fillText("LV. 07", x + 61, y + 466);
  ctx.fillStyle = C.orange;
  ctx.fillRect(x + 60, y + 495, width - 120, 10);
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
  giantType(ctx, ["BACK", "COURT"], 1136, 68, 244, 218, C.ink, .12, "right");
  platformMeta(ctx);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 24);
  ctx.fillText("농구할 땐", 62, 694);
  ctx.font = font(900, 76);
  ctx.fillText("빽코트", 58, 782);
  ctx.fillRect(62, 828, 58, 7);
  ctx.fillStyle = C.ink;
  ctx.fillRect(58, 890, 354, 88);
  storeMarks(ctx, 86, 914);
  ctx.fillStyle = "rgba(255,255,255,.28)";
  ctx.fillRect(188, 912, 2, 42);
  ctx.fillStyle = C.orange;
  ctx.font = font(900, 25);
  ctx.fillText("출시 예정", 226, 947);
  heroIcon(ctx, 624, 606, 386, -3);
  courtLines(ctx, C.ink, .18);
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
  mapArtwork(ctx, 536, 152, 544, 928);
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
  liveCard(ctx, 70, 414, 408, 650, "live");
  liveCard(ctx, 604, 372, 408, 650, "meetup");
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
  radarArtwork(ctx, 790, 410);
  ctx.fillStyle = C.white;
  ctx.font = font(900, 22);
  ctx.textAlign = "center";
  ctx.fillText("GPS 출석", 790, 684);
  ctx.textAlign = "left";
  ctx.fillStyle = "#1c1c1c";
  ctx.fillRect(560, 748, 460, 232);
  ctx.fillStyle = C.orange;
  [0, 1, 2].forEach((index) => ctx.fillRect(598 + index * 116, 915 - index * 46, 76, 34 + index * 46));
  ctx.fillStyle = C.white;
  ctx.font = font(900, 20);
  trackedText(ctx, "COURT RANKING", 598, 800, 2.5);
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
  feedArtwork(ctx, 54, 474, 420, 642);
  profileArtwork(ctx, 606, 422, 474, 658);
  roundedFill(ctx, 390, 889, 300, 74, 37, C.orange);
  ctx.fillStyle = C.ink;
  ctx.font = font(900, 23);
  ctx.textAlign = "center";
  ctx.fillText("일상에서, 다시 코트로.", 540, 935);
  ctx.textAlign = "left";
}

const renderers = [slide1];

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
  downloadSlide(1);
});

Promise.all(Object.entries(sources).map(async ([key, src]) => {
  images[key] = await loadImage(src);
})).then(() => document.fonts.ready).then(renderAll).catch((error) => {
  console.error(error);
  document.body.dataset.error = "true";
});
