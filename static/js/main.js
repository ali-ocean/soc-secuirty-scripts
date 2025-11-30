document.addEventListener('DOMContentLoaded', function() {
    const flashMessages = document.querySelectorAll('.alert');
    flashMessages.forEach(msg => {
        setTimeout(() => {
            msg.style.opacity = '0';
            setTimeout(() => msg.remove(), 300);
        }, 5000);
    });

    const forms = document.querySelectorAll('form[onsubmit*="confirm"]');
    forms.forEach(form => {
        form.addEventListener('submit', function(e) {
            const message = form.getAttribute('onsubmit').match(/'([^']+)'/)[1];
            if (!confirm(message)) {
                e.preventDefault();
            }
        });
    });
});

function toggleSelectAll(source) {
    const checkboxes = document.querySelectorAll('input[name="host_ids"]');
    checkboxes.forEach(checkbox => {
        checkbox.checked = source.checked;
    });
}
