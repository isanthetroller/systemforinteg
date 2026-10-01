/**
 * SecurePark Student Portal - API location
 *
 * Production (InfinityFree):  htdocs/student/  ->  API at htdocs/api/  ("../api")
 * Local development:          /web-app-student/ served from the repo root -> "../web-app-admin/api"
 *
 * To point the portal somewhere else, set window.SECUREPARK_API_URL before this file loads.
 */
window.SECUREPARK_API_URL = window.SECUREPARK_API_URL ||
  (window.location.pathname.indexOf('/web-app-student/') !== -1 ? '../web-app-admin/api' : '../api');

// Gate clips: the shared 5 second clip lives with the admin app's assets (htdocs/assets/ on the server)
window.SECUREPARK_ASSETS_URL = window.SECUREPARK_ASSETS_URL ||
  (window.location.pathname.indexOf('/web-app-student/') !== -1 ? '../web-app-admin/assets' : '../assets');
