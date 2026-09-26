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
