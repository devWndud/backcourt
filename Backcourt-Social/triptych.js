const params = new URLSearchParams(window.location.search);
const panel = Number(params.get("panel"));

if (panel >= 1 && panel <= 3) {
  document.body.classList.add("export-mode", `panel-${panel}`);
}

if (params.get("panorama") === "1") {
  document.body.classList.add("panorama-mode");
}
