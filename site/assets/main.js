document.documentElement.classList.add("js");

document.querySelectorAll("[data-year]").forEach((element) => {
  element.textContent = new Date().getFullYear();
});

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
if (reducedMotion.matches) {
  document.querySelectorAll("video[autoplay]").forEach((video) => video.removeAttribute("autoplay"));
}

const observer = "IntersectionObserver" in window
  ? new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8%", threshold: 0.08 })
  : null;

document.querySelectorAll(".reveal").forEach((element) => {
  if (observer) observer.observe(element);
  else element.classList.add("is-visible");
});

const demoToggle = document.querySelector(".demo-toggle");
const demoVideos = document.querySelectorAll("video.demo-screen");
if (demoToggle) {
  let demosPaused = reducedMotion.matches;
  const updateDemos = () => {
    demoVideos.forEach((video) => {
      if (demosPaused) video.pause();
      else video.play().catch(() => { video.controls = true; });
    });
    demoToggle.textContent = demosPaused ? "Play demos" : "Pause demos";
    demoToggle.setAttribute("aria-pressed", String(demosPaused));
  };
  const widgetPreview = document.querySelector("#widget-preview");
  const widgetDescriptions = {
    single: "One habit, with a month of history.",
    three: "Three habits, with ten days of progress.",
    six: "Six habits, with ten days of progress."
  };
  document.querySelectorAll("[data-widget]").forEach((button) => {
    button.addEventListener("click", () => {
      const size = button.dataset.widget;
      if (button.getAttribute("aria-pressed") === "true") return;
      document.querySelectorAll("[data-widget]").forEach((item) => {
        item.setAttribute("aria-pressed", String(item === button));
      });
      document.querySelector(".widget-description").textContent = widgetDescriptions[size];
      widgetPreview.pause();
      widgetPreview.poster = `assets/widget-${size}-demo.png?v=2`;
      widgetPreview.setAttribute("aria-label", `${widgetDescriptions[size]} An iPhone Home Screen demo showing taps to record progress.`);
      widgetPreview.querySelectorAll("source").forEach((source) => {
        const extension = source.type === "video/webm" ? "webm" : "mp4";
        source.src = `assets/widget-${size}-demo.${extension}?v=2`;
      });
      widgetPreview.querySelector("a").href = `assets/widget-${size}-demo.mp4?v=2`;
      widgetPreview.autoplay = !demosPaused;
      widgetPreview.load();
      if (!demosPaused) widgetPreview.play().catch(() => { widgetPreview.controls = true; });
    });
  });
  demoToggle.hidden = false;
  updateDemos();
  demoToggle.addEventListener("click", () => {
    demosPaused = !demosPaused;
    updateDemos();
  });
  reducedMotion.addEventListener("change", (event) => {
    demosPaused = event.matches;
    updateDemos();
  });
}
