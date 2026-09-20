const query = new URLSearchParams(window.location.search);

if (query.get("export") === "1") {
  document.body.classList.add("export-mode");
}
