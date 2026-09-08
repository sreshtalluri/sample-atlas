import unittest
import numpy as np
from worker import filtered_top_k, unit_rows


class RetrievalTests(unittest.TestCase):
    def test_default_returns_every_eligible_vector_in_order(self):
        rng = np.random.default_rng(7)
        vectors = unit_rows(rng.normal(size=(713, 32)))
        query = unit_rows(rng.normal(size=32))
        ids = np.arange(1, 714)
        eligible = ids[::2].tolist()
        result = filtered_top_k(vectors, ids, query, eligible)
        expected = sorted(eligible, key=lambda i: (-float(vectors[i - 1] @ query), i))
        self.assertEqual(result, expected)
        self.assertGreater(len(result), 200)
        self.assertEqual(filtered_top_k(vectors, ids, query, eligible, k=10), expected[:10])

    def test_empty_and_tied_results(self):
        vectors = np.ones((4, 2), dtype=np.float32)
        ids = np.array([4, 1, 3, 2])
        self.assertEqual(filtered_top_k(vectors, ids, np.ones(2), [], k=2), [])
        self.assertEqual(filtered_top_k(vectors, ids, np.ones(2), [1, 2, 3, 4], k=2), [1, 2])


if __name__ == "__main__":
    unittest.main()
