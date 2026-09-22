const COPY_STORAGE_KEY = "backcourt-store-screens-copy-v1";
const editableCopy = [...document.querySelectorAll("[data-edit]")];
const defaultCopy = Object.fromEntries(
  editableCopy.map((element) => [element.dataset.edit, element.innerHTML]),
);

function readSavedCopy() {
  try {
    return JSON.parse(localStorage.getItem(COPY_STORAGE_KEY) || "{}");
  } catch (_) {
    return {};
  }
}

function saveCopy() {
  const copy = Object.fromEntries(
    editableCopy.map((element) => [element.dataset.edit, element.innerHTML]),
  );
  localStorage.setItem(COPY_STORAGE_KEY, JSON.stringify(copy));
}

const savedCopy = readSavedCopy();
for (const element of editableCopy) {
  const saved = savedCopy[element.dataset.edit];
  if (typeof saved === "string") element.innerHTML = saved;
  element.addEventListener("input", saveCopy);
  element.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && element.tagName === "P") event.preventDefault();
  });
}

document.querySelector("#reset-copy")?.addEventListener("click", () => {
  for (const element of editableCopy) {
    element.innerHTML = defaultCopy[element.dataset.edit];
  }
  localStorage.removeItem(COPY_STORAGE_KEY);
});

const exportSlide = Number(new URLSearchParams(location.search).get("export"));
if (exportSlide >= 1 && exportSlide <= 4) {
  document.body.classList.add("export-mode");
  document.querySelector(`.creative[data-slide="${exportSlide}"]`)?.classList.add("is-export");
}
