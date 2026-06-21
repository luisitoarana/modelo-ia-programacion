# Complejidad algorítmica

## Notación Big-O (cota superior)

Describe cómo crece el tiempo (o espacio) cuando crece la entrada.

| Notación | Nombre | Ejemplo típico |
|----------|--------|----------------|
| O(1) | constante | acceso por índice |
| O(log n) | logarítmica | búsqueda binaria |
| O(n) | lineal | recorrer una lista |
| O(n log n) | lineal-logarítmica | merge sort, Timsort |
| O(n²) | cuadrática | burbuja, dos bucles anidados |
| O(2ⁿ) | exponencial | fib recursivo ingenuo |
| O(n!) | factorial | permutaciones |

## Reglas prácticas

1. Constantes se descartan: O(2n) = O(n).
2. Términos de menor orden se descartan: O(n² + n) = O(n²).
3. Bucles anidados multiplican: anidar `for` dos veces = O(n²).

## Espacial

Cuenta solo memoria adicional, no la entrada en sí. Una solución in-place puede
ser O(1) auxiliar pese a trabajar sobre una lista de tamaño n.

## Por qué importa

La elección del algoritmo determina si tu programa es viable a escala. Entender
complejidad permite **predecir** y **comparar** sin medir cada vez.
