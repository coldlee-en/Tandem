"use strict";

// Repository identity is supplied by the GitHub Pages workflow, never guessed.
// No download is advertised until a publisher explicitly marks a release ready.
(async function configureRepositoryLinks() {
  try {
    const response = await fetch("./site-config.json", { cache: "no-store" });
    if (!response.ok) return;
    const config = await response.json();
    if (typeof config.repositoryUrl !== "string") return;
    const url = new URL(config.repositoryUrl);
    const match = url.pathname.match(/^\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/?$/);
    if (url.protocol !== "https:" || url.hostname !== "github.com" || url.username || url.password || !match) return;
    const repository = `https://github.com/${match[1]}/${match[2]}`;
    const branch = typeof config.defaultBranch === "string" && config.defaultBranch ? config.defaultBranch : "main";

    document.querySelectorAll("[data-repository-link]").forEach(link => {
      link.href = repository;
      link.hidden = false;
    });
    document.querySelectorAll("[data-repository-file]").forEach(link => {
      const path = link.dataset.repositoryFile;
      if (!/^[A-Za-z0-9_.\/-]+$/.test(path) || path.includes("..")) return;
      link.href = `${repository}/blob/${encodeURIComponent(branch)}/${path}`;
      link.hidden = false;
    });
    document.querySelectorAll("[data-repository-pending]").forEach(element => { element.hidden = true; });
    if (config.releaseReady === true) {
      document.querySelectorAll("[data-release-link]").forEach(link => {
        link.href = `${repository}/releases/latest`;
        link.hidden = false;
      });
      document.querySelectorAll("[data-release-description]").forEach(element => {
        element.textContent = "A release has been published. Check its notes for signing requirements, build contents, and validation status.";
      });
      document.querySelectorAll("[data-release-status]").forEach(element => { element.textContent = "Read release notes"; });
    }
  } catch (_) {
    // Local previews and an unavailable config retain the honest source-only UI.
  }
})();
