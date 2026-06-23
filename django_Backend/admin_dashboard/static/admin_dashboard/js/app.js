/* =============================================
   Fix-It Admin Dashboard — Alpine.js + HTMX Helpers
   Tailwind CSS v4 version
   ============================================= */

// ----- Alpine.js Stores -----
document.addEventListener('alpine:init', () => {

    // Sidebar toggle (mobile)
    Alpine.store('sidebar', {
        open: false,
        toggle() {
            this.open = !this.open;
        },
        close() {
            this.open = false;
        }
    });

    // Toast notification store
    Alpine.store('toast', {
        items: [],
        show(message, type = 'success', duration = 4000) {
            const id = Date.now();
            this.items.push({ id, message, type });
            setTimeout(() => this.remove(id), duration);
        },
        remove(id) {
            this.items = this.items.filter(item => item.id !== id);
        },
        success(msg) { this.show(msg, 'success'); },
        error(msg) { this.show(msg, 'danger'); },
        warning(msg) { this.show(msg, 'warning'); },
        info(msg) { this.show(msg, 'info'); }
    });

    // Confirm dialog store
    Alpine.store('confirm', {
        show: false,
        title: '',
        message: '',
        action: null,
        open(title, message, actionFn) {
            this.title = title;
            this.message = message;
            this.action = actionFn;
            this.show = true;
        },
        cancel() {
            this.show = false;
            this.action = null;
        },
        confirm() {
            if (this.action) this.action();
            this.show = false;
            this.action = null;
        }
    });
});

// ----- HTMX Event Handlers -----

// Show toast on Django message events after HTMX swaps
document.addEventListener('htmx:afterRequest', (event) => {
    if (event.detail && event.detail.xhr) {
        const xhr = event.detail.xhr;
        const toastHeader = xhr.getResponseHeader('X-Toast-Message');
        const toastType = xhr.getResponseHeader('X-Toast-Type') || 'success';
        if (toastHeader) {
            const store = Alpine.store('toast');
            if (store) {
                store.show(decodeURIComponent(toastHeader), toastType);
            }
        }
    }
});

// Scroll chat messages to bottom on load
document.addEventListener('htmx:afterSettle', () => {
    const chatBox = document.getElementById('chat-messages');
    if (chatBox) {
        chatBox.scrollTop = chatBox.scrollHeight;
    }
});

// Close sidebar on navigation (mobile)
document.addEventListener('htmx:pushedIntoHistory', () => {
    const sidebar = Alpine.store('sidebar');
    if (sidebar && sidebar.open) {
        sidebar.close();
    }
});

// ----- Utility Functions -----

// Format number as Nigerian Naira
function formatNaira(amount) {
    const num = parseFloat(amount);
    if (isNaN(num)) return '₦0.00';
    return '₦' + num.toLocaleString('en-NG', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });
}

// Format date in Lagos timezone
function formatLagosDate(dateStr) {
    if (!dateStr) return '—';
    const date = new Date(dateStr);
    return date.toLocaleString('en-NG', {
        timeZone: 'Africa/Lagos',
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

// ----- Chart.js Defaults -----
if (typeof Chart !== 'undefined') {
    Chart.defaults.font.family = "'Inter', 'Segoe UI', Tahoma, sans-serif";
    Chart.defaults.font.size = 12;
    Chart.defaults.color = '#6b7280';
    Chart.defaults.plugins.legend.labels.usePointStyle = true;
    Chart.defaults.plugins.legend.labels.padding = 16;
}

// ----- Auto-dismiss alerts -----
document.addEventListener('DOMContentLoaded', () => {
    // Scroll chat to bottom on page load
    const chatBox = document.getElementById('chat-messages');
    if (chatBox) {
        chatBox.scrollTop = chatBox.scrollHeight;
    }
});

// ----- Django CSRF token helper for HTMX -----
document.addEventListener('htmx:configRequest', (event) => {
    const csrfToken = document.querySelector('[name=csrfmiddlewaretoken]');
    if (csrfToken) {
        event.detail.headers['X-CSRFToken'] = csrfToken.value;
    }
});