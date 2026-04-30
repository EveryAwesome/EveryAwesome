// Fetch the pre-built dataset and pass it to Elm as a flag.
// /entries.json is served from webapp/static/entries.json.
export const flags = async () => {
  const response = await fetch("/entries.json")
  if (!response.ok) {
    throw new Error(`Failed to load /entries.json: ${response.status}`)
  }
  return await response.json()
}

export const onReady = ({ app }) => {
  console.log("EveryAwesome ready", app)
}
