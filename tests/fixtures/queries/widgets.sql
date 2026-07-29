-- name: GetWidget :one
SELECT id, name FROM widgets WHERE id = ?;

-- name: ListWidgets :many
SELECT id, name FROM widgets ORDER BY name;
