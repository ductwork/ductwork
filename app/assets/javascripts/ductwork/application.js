function formatElapsed(milliseconds) {
  const elapsed = Math.floor(Math.max(milliseconds, 0) / 1000);
  const hours = Math.floor(elapsed / 3600);
  const minutes = Math.floor((elapsed % 3600) / 60);
  const seconds = elapsed % 60;
  const parts = [];

  if (hours > 0) parts.push(`${hours}h`);
  if (minutes > 0) parts.push(`${minutes}m`);
  if (seconds > 0 || parts.length === 0) parts.push(`${seconds}s`);

  return parts.join(' ');
}

function startTimers() {
  const timers = document.querySelectorAll('[data-started-at]');

  function tick() {
    timers.forEach(function(timer) {
      timer.textContent = formatElapsed(Date.now() - new Date(timer.dataset.startedAt));
    });
  }

  if (timers.length > 0) {
    tick();
    setInterval(tick, 1000);
  }
}

function linkRows() {
  document.querySelectorAll('tr[data-href]').forEach(function(row) {
    row.addEventListener('click', function(event) {
      const selectingText = !window.getSelection().isCollapsed;

      if (selectingText || event.target.closest('a')) return;

      window.location.href = row.dataset.href;
    });
  });
}

function closeMenus(except) {
  document.querySelectorAll('details.menu[open]').forEach(function(menu) {
    if (menu !== except) menu.removeAttribute('open');
  });
}

function dismissMenus() {
  document.addEventListener('click', function(event) {
    closeMenus(event.target.closest('details.menu'));
  });

  document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') closeMenus();
  });
}

document.addEventListener('DOMContentLoaded', function() {
  startTimers();
  linkRows();
  dismissMenus();
});
