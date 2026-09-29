/**
 * SecurePark Web App - Pass Rules page
 *
 * A read-only reference of how passes are checked at the gates. There is nothing to configure:
 * visitor day passes are valid all day on their date.
 */
(function () {
  'use strict';

  document.addEventListener('sp:app-ready', () => {
    if (window.SP && SP.registerView) {
      SP.registerView('settingsView', document.getElementById('navSettingsBtn'));
    }
  });
})();
