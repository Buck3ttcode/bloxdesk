// BloxDesk Documentation Script
document.addEventListener("DOMContentLoaded", () => {

  // 1. Smooth Scroll Spy for Table of Contents & Sidebar
  const sections = document.querySelectorAll(".doc-content section[id]");
  const tocLinks = document.querySelectorAll(".toc-link");
  const sidebarLinks = document.querySelectorAll(".sidebar-link");

  function onScroll() {
    const scrollPos = window.scrollY + 100;
    let currentId = "";

    sections.forEach(section => {
      const top = section.offsetTop;
      const height = section.offsetHeight;
      if (scrollPos >= top && scrollPos < top + height) {
        currentId = section.getAttribute("id");
      }
    });

    if (currentId) {
      tocLinks.forEach(link => {
        link.classList.toggle("active", link.getAttribute("href") === `#${currentId}`);
      });
      sidebarLinks.forEach(link => {
        link.classList.toggle("active", link.getAttribute("href") === `#${currentId}`);
      });
    }
  }

  window.addEventListener("scroll", onScroll);
  onScroll();

  // 2. Documentation Search Filter
  const searchInput = document.getElementById("doc-search-input");
  if (searchInput) {
    searchInput.addEventListener("input", (e) => {
      const query = e.target.value.toLowerCase().trim();
      if (!query) {
        sections.forEach(sec => sec.style.display = "");
        return;
      }

      sections.forEach(section => {
        const text = section.innerText.toLowerCase();
        if (text.includes(query)) {
          section.style.display = "";
        } else {
          section.style.display = "none";
        }
      });
    });
  }

  // 3. One-Click Code Snippet Copy
  window.copySnippet = function(button, elementId) {
    const el = document.getElementById(elementId);
    if (!el) return;
    navigator.clipboard.writeText(el.innerText || el.textContent).then(() => {
      const orig = button.textContent;
      button.textContent = "Copied";
      button.style.borderColor = "var(--c-bright)";
      button.style.color = "var(--c-bright)";
      setTimeout(() => {
        button.textContent = orig;
        button.style.borderColor = "";
        button.style.color = "";
      }, 1800);
    });
  };

  // 4. Copy Discord Handle
  window.copyDiscordHandle = function(btn) {
    navigator.clipboard.writeText("bucketcode").then(() => {
      const orig = btn.innerText;
      btn.innerText = "Copied: bucketcode";
      setTimeout(() => {
        btn.innerText = orig;
      }, 2000);
    });
  };
});
