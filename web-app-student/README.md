# SecurePark — Student Portal

Mobile-first portal for registered vehicle owners (students and employees). Deployed to
`htdocs/student/` and talks to the shared API at `../api` (see `js/config.js`; locally it uses
`../web-app-admin/api`). Setup and deployment are in the [main README](../README.md).

- **Sign in** with the student / employee ID. The login is created by the Security Office when the
  vehicle is registered; the temporary password must be changed at first sign-in.
- **My Pass** — signed QR (tap for full screen at the gate), standing, authorized drivers, save as image.
- **Strikes** — 3-strike meter per vehicle, warnings / violations, recent gate activity.
- **Account** — profile, change password.

The portal only calls `student.php` and `auth.php`; the server scopes every query to the signed-in
owner. This folder shares no files with the admin portal (it has its own copies of `qrcode.min.js`
and `aes.js`).
