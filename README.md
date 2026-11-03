# Interview Assistant

A Windows desktop prompt window for preparing concise interview answers. Select a question on screen, and an independently running Codex CLI session can draft a response using the context you provide. The window supports a translucent background, answer navigation and optional highlighting.

## Requirements

- Windows with Windows PowerShell and a graphical desktop.
- Python 3.9 or later, including `pythonw.exe`, available on `PATH`.
- Node.js and npm, the [Codex CLI](https://developers.openai.com/codex/cli/), a ChatGPT account with access to Codex and an internet connection.

Install the Codex CLI using the official instructions, then run `codex login` in a terminal and choose ChatGPT sign-in. Account eligibility, model access and usage limits depend on the account. Sign-in is handled by Codex; do not put a password, access token or API key in this project.

## Get started

1. Download or clone the repository, then open `Start.cmd`. On first launch the app creates local context files from the example templates. Use **Career facts** to add only the facts you want used, and **Interview context** to add the current employer and role. Leave unknown facts out. The launcher uses a PowerShell execution policy override for that process only; it does not persistently change the policy.
2. To start it manually from the project directory without the launcher's policy override, if your system permits it, run:

   ```powershell
   powershell.exe -NoProfile -STA -File .\InterviewNotes.ps1
   ```

3. Use **Sign in** if needed, then click **Connect**. The application checks the locally signed-in Codex CLI and makes a small live request before reporting that it is connected. Starting the application does not connect it to an existing ChatGPT conversation.
4. Click **Capture question**, drag a rectangle around the question, and wait for the answer. Press `Esc` to cancel the selection. Use left and right arrows to navigate saved answers; use the **Highlight** checkbox to turn emphasis on or off. Click **Disconnect** to cancel an active request.

This is a user-initiated screenshot workflow: it does not automatically read or monitor browser pages. Check the displayed answer for accuracy before using it; the model can misunderstand an image or infer unsupported details.

## Privacy and local files

Only the region you select is captured. The selected image, your career and interview context, and the answer guidelines are sent to OpenAI through Codex for generation. Review what you include before capturing or entering it. The app does not access your browser login, camera or microphone.

Screenshots are stored temporarily in `captures/` and normally deleted after processing or stopping. If the app or worker is forcibly terminated, or a capture is superseded before processing, an image may remain there; check and remove it yourself if necessary. Context, generated answers, session files and settings are stored locally and excluded by `.gitignore`. Git ignore rules do not protect data that was previously committed, explicitly force-added or shared separately.

## Tests

Run the offline worker checks with `python -m unittest discover -s tests -v`. They use temporary synthetic data and do not contact an AI service.

## License

[MIT](LICENSE)
