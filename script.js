// BloxDesk Documentation Script
document.addEventListener("DOMContentLoaded", () => {

  // ==========================================================================
  // 1. Smooth Scroll Spy for Table of Contents & Sidebar
  // ==========================================================================
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

  // ==========================================================================
  // 2. Interactive Documentation Search Engine (Dropdown with Highlights)
  // ==========================================================================
  const searchInput = document.getElementById("doc-search-input");
  const searchDropdown = document.getElementById("search-dropdown");

  // Build Search Index from Page Content
  const searchIndex = [];
  sections.forEach(section => {
    const id = section.getAttribute("id");
    const h2 = section.querySelector("h2");
    const h3s = section.querySelectorAll("h3");
    const title = h2 ? h2.innerText : (h3s[0] ? h3s[0].innerText : id);

    // Find category from sidebar link
    let category = "Documentation";
    const matchingSidebar = document.querySelector(`.sidebar-link[href="#${id}"]`);
    if (matchingSidebar) {
      const catBlock = matchingSidebar.closest(".sidebar-category");
      if (catBlock) {
        const catTitle = catBlock.querySelector(".sidebar-category-title");
        if (catTitle) category = catTitle.innerText;
      }
    }

    // Extract text content
    const paragraphs = Array.from(section.querySelectorAll("p, li, td, code"))
      .map(el => el.innerText.trim())
      .filter(t => t.length > 5);

    searchIndex.push({
      id,
      title,
      category,
      content: paragraphs.join(" ")
    });
  });

  let selectedIndex = -1;

  function renderSearchResults(query) {
    if (!query) {
      searchDropdown.classList.remove("active");
      searchDropdown.innerHTML = "";
      selectedIndex = -1;
      return;
    }

    const q = query.toLowerCase();
    const matches = [];

    searchIndex.forEach(item => {
      const inTitle = item.title.toLowerCase().indexOf(q);
      const inContent = item.content.toLowerCase().indexOf(q);

      if (inTitle !== -1 || inContent !== -1) {
        // Generate snippet around match
        let snippet = "";
        if (inContent !== -1) {
          const start = Math.max(0, inContent - 30);
          const end = Math.min(item.content.length, inContent + 70);
          snippet = (start > 0 ? "..." : "") + item.content.slice(start, end) + (end < item.content.length ? "..." : "");
          // Highlight match in snippet
          const regex = new RegExp(`(${escapeRegExp(query)})`, "gi");
          snippet = snippet.replace(regex, "<mark>$1</mark>");
        } else {
          snippet = item.content.slice(0, 90) + "...";
        }

        matches.push({
          ...item,
          score: inTitle !== -1 ? 10 : 1,
          snippet
        });
      }
    });

    // Sort: Title matches first
    matches.sort((a, b) => b.score - a.score);

    if (matches.length === 0) {
      searchDropdown.innerHTML = `<div class="search-no-results">No documentation results for "<strong>${escapeHtml(query)}</strong>"</div>`;
      searchDropdown.classList.add("active");
      selectedIndex = -1;
      return;
    }

    selectedIndex = 0;
    searchDropdown.innerHTML = matches.slice(0, 6).map((match, idx) => `
      <div class="search-result-item ${idx === 0 ? 'selected' : ''}" data-target="${match.id}">
        <div class="search-result-title">
          <span>${escapeHtml(match.title)}</span>
          <span class="search-result-category">${escapeHtml(match.category)}</span>
        </div>
        <div class="search-result-snippet">${match.snippet}</div>
      </div>
    `).join("");

    searchDropdown.classList.add("active");

    // Add click listeners to items
    searchDropdown.querySelectorAll(".search-result-item").forEach(item => {
      item.addEventListener("click", () => {
        jumpToSection(item.dataset.target);
      });
    });
  }

  function jumpToSection(targetId) {
    const el = document.getElementById(targetId);
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "start" });
      el.classList.add("highlight-pulse");
      setTimeout(() => el.classList.remove("highlight-pulse"), 1800);
    }
    searchDropdown.classList.remove("active");
    if (searchInput) searchInput.value = "";
  }

  function escapeHtml(str) {
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function escapeRegExp(string) {
    return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  if (searchInput) {
    searchInput.addEventListener("input", (e) => {
      renderSearchResults(e.target.value.trim());
    });

    searchInput.addEventListener("keydown", (e) => {
      const items = searchDropdown.querySelectorAll(".search-result-item");
      if (!searchDropdown.classList.contains("active") || items.length === 0) return;

      if (e.key === "ArrowDown") {
        e.preventDefault();
        selectedIndex = (selectedIndex + 1) % items.length;
        updateSelection(items);
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        selectedIndex = (selectedIndex - 1 + items.length) % items.length;
        updateSelection(items);
      } else if (e.key === "Enter") {
        e.preventDefault();
        if (selectedIndex >= 0 && items[selectedIndex]) {
          jumpToSection(items[selectedIndex].dataset.target);
        }
      } else if (e.key === "Escape") {
        searchDropdown.classList.remove("active");
      }
    });

    function updateSelection(items) {
      items.forEach((item, idx) => {
        item.classList.toggle("selected", idx === selectedIndex);
        if (idx === selectedIndex) {
          item.scrollIntoView({ block: "nearest" });
        }
      });
    }
  }

  // Close search when clicking outside
  document.addEventListener("click", (e) => {
    if (!e.target.closest(".header-search")) {
      if (searchDropdown) searchDropdown.classList.remove("active");
    }
  });

  // Global Keyboard Shortcut: Pressing '/' focuses search
  document.addEventListener("keydown", (e) => {
    if (e.key === "/" && document.activeElement !== searchInput && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
      e.preventDefault();
      if (searchInput) {
        searchInput.focus();
        searchInput.select();
      }
    }
  });

  // ==========================================================================
  // 3. One-Click Code Snippet Copy
  // ==========================================================================
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

  // ==========================================================================
  // 4. Copy Discord Handle
  // ==========================================================================
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
