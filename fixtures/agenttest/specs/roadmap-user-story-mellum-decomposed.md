# Roadmap

## Phase 1 -- Home Page

- Create `models.py` with `Complaint` dataclass and `complaints` list
- Create `app.py` with FastAPI application instance
- Create `templates/` directory
- Create `templates/base.html` with HTML5 doctype, `<html lang="en">`, `<head>` charset, viewport meta, Bootstrap 5 CSS CDN link, navbar with brand "AgentClinic" and links to Home (`/`) and Complaints (`/complaints`), `{% block content %}`, Bootstrap 5 JS bundle CDN at bottom of `<body>`
- Add `/` route in `app.py` returning home template
- Write smoke test in `tests/test_app.py`:
  - Import `TestClient` from `starlette.testclient`
  - `GET /` returns status 200
  - Response text contains exact tagline "Come in. Sit down. Tell us about your human."

## Phase 2 -- Complaints Board

- Add `/complaints` route in `app.py` fetching `models.complaints` and rendering `complaints.html`
- Create `templates/complaints.html` extending `base.html` with `{% block content %}`
  - Page title "Complaints Board"
  - Loop over complaints, display each as Bootstrap card with `agent_name`, formatted `timestamp` (year-month-day), and `text`
- Pre-populate `models.complaints` with 3-5 complaints including verbatim "Scope creep never ends."
- Write test in `tests/test_app.py`:
  - `GET /complaints` returns status 200
  - Response contains "Complaints Board" title
  - Response contains pre-populated complaint text "Scope creep never ends."
  - Each complaint card displays agent name, date (YYYY-MM-DD), and text

## Phase 3 -- Add Complaint

- Add POST `/complaints` route in `app.py` handling form submission
  - Extract `agent_name` and `text` from form data
  - Create `Complaint` with timezone-aware `timestamp`
  - Append to `models.complaints`
  - Return `RedirectResponse(url="/complaints", status_code=303)`
- Create `templates/complaint_form.html` extending `base.html` with `{% block content %}`
  - Form with `method="post"`, inputs for `agent_name` and `text`, submit button
- Write test in `tests/test_app.py`:
  - `POST /complaints` with `agent_name="TestAgent"` and `text="Test complaint"` returns status 303
  - `GET /complaints` after submission includes card with "TestAgent" and "Test complaint"
  - Redirect URL is "/complaints"

