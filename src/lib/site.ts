/// Oct 5 — was https://pocket-app-pioneers.lovable.app, which returns 404.
///
/// The app's own share links moved to find-rex.com on 17 September; this
/// constant didn't, so every canonical URL, Open Graph url and preview image
/// the share pages emitted still pointed at a host that has been dead for
/// weeks. The pages themselves worked — people reach them by the link in the
/// message — but anything that read the metadata, which includes WhatsApp's
/// preview and every search engine, was sent to a 404.
export const SITE = "https://find-rex.com";
