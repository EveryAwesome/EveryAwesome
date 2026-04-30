// Fetch the pre-built dataset and pass it to Elm as a flag.
// Relative path so the app works under any base (root in dev,
// /<repo>/ on GitHub Pages).
export const flags = async () => {
  const response = await fetch("entries.json")
  if (!response.ok) {
    throw new Error(`Failed to load entries.json: ${response.status}`)
  }
  return await response.json()
}

export const onReady = ({ app }) => {
  console.log("EveryAwesome ready", app)
}
