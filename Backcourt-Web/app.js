const toast = document.querySelector("#store-toast");
let hideTimer;

document.querySelectorAll("[data-store]").forEach((button) => {
  button.addEventListener("click", () => {
    window.clearTimeout(hideTimer);
    toast.textContent = `${button.dataset.store} 출시 준비 중`;
    toast.classList.add("is-visible");
    hideTimer = window.setTimeout(() => {
      toast.classList.remove("is-visible");
    }, 2200);
  });
});
