import { useState, useEffect } from 'react';

const API_URL = process.env.REACT_APP_API_URL || 'http://localhost:3000';

function App() {
  const [products, setProducts] = useState([]);
  const [cart, setCart] = useState([]);
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('products');

  useEffect(() => {
    fetchProducts();
    const savedUser = localStorage.getItem('user');
    if (savedUser) setUser(JSON.parse(savedUser));
  }, []);

  const fetchProducts = async () => {
    try {
      const res = await fetch(`${API_URL}/api/v1/products`);
      const data = await res.json();
      setProducts(data.products || []);
    } catch (err) {
      console.error('Failed to fetch products:', err);
    } finally {
      setLoading(false);
    }
  };

  const addToCart = (product) => {
    setCart(prev => {
      const existing = prev.find(i => i._id === product._id);
      if (existing) return prev.map(i => i._id === product._id ? { ...i, qty: i.qty + 1 } : i);
      return [...prev, { ...product, qty: 1 }];
    });
  };

  const handleLogin = async (email, password) => {
    try {
      const res = await fetch(`${API_URL}/api/v1/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });
      const data = await res.json();
      if (res.ok) {
        setUser(data.user);
        localStorage.setItem('user', JSON.stringify(data.user));
        localStorage.setItem('token', data.accessToken);
      }
    } catch (err) {
      console.error('Login failed:', err);
    }
  };

  const placeOrder = async () => {
    if (!user) return alert('Please login first');
    const token = localStorage.getItem('token');
    const items = cart.map(i => ({ productId: i._id, quantity: i.qty, price: i.price }));
    try {
      const res = await fetch(`${API_URL}/api/v1/orders`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ userId: user.id, items, shippingAddress: { city: 'New York' } }),
      });
      const data = await res.json();
      if (res.ok) {
        alert(`Order placed! ID: ${data.orderId}`);
        setCart([]);
      }
    } catch (err) {
      console.error('Order failed:', err);
    }
  };

  const cartTotal = cart.reduce((sum, i) => sum + i.price * i.qty, 0);

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', maxWidth: 1200, margin: '0 auto', padding: 20 }}>
      {/* Header */}
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        background: '#1a1a2e', color: 'white', padding: '15px 20px', borderRadius: 8 }}>
        <h1 style={{ margin: 0 }}>🛒 AKS E-Commerce</h1>
        <div>
          {user ? (
            <span>👤 {user.name} | Cart: {cart.length} items (${cartTotal.toFixed(2)})</span>
          ) : (
            <button onClick={() => handleLogin('demo@test.com', 'password123')}
              style={{ padding: '8px 16px', background: '#e94560', color: 'white',
                border: 'none', borderRadius: 4, cursor: 'pointer' }}>
              Login (Demo)
            </button>
          )}
        </div>
      </header>

      {/* Nav */}
      <nav style={{ margin: '20px 0', display: 'flex', gap: 10 }}>
        {['products', 'cart', 'orders'].map(tab => (
          <button key={tab} onClick={() => setActiveTab(tab)}
            style={{ padding: '8px 20px', background: activeTab === tab ? '#1a1a2e' : '#eee',
              color: activeTab === tab ? 'white' : 'black', border: 'none',
              borderRadius: 4, cursor: 'pointer', textTransform: 'capitalize' }}>
            {tab} {tab === 'cart' && cart.length > 0 ? `(${cart.length})` : ''}
          </button>
        ))}
      </nav>

      {/* Products Tab */}
      {activeTab === 'products' && (
        <div>
          <h2>Products</h2>
          {loading ? <p>Loading...</p> : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: 20 }}>
              {products.length === 0 ? (
                <p>No products yet. Add some via the API!</p>
              ) : products.map(p => (
                <div key={p._id} style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16 }}>
                  <h3 style={{ margin: '0 0 8px' }}>{p.name}</h3>
                  <p style={{ color: '#666', fontSize: 14 }}>{p.description}</p>
                  <p style={{ fontWeight: 'bold', fontSize: 18, color: '#e94560' }}>${p.price}</p>
                  <p style={{ fontSize: 12, color: '#999' }}>Stock: {p.stock}</p>
                  <button onClick={() => addToCart(p)}
                    style={{ width: '100%', padding: '8px', background: '#1a1a2e', color: 'white',
                      border: 'none', borderRadius: 4, cursor: 'pointer', marginTop: 8 }}>
                    Add to Cart
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Cart Tab */}
      {activeTab === 'cart' && (
        <div>
          <h2>Shopping Cart</h2>
          {cart.length === 0 ? <p>Cart is empty</p> : (
            <>
              {cart.map(item => (
                <div key={item._id} style={{ display: 'flex', justifyContent: 'space-between',
                  padding: 12, borderBottom: '1px solid #eee' }}>
                  <span>{item.name}</span>
                  <span>x{item.qty} = ${(item.price * item.qty).toFixed(2)}</span>
                </div>
              ))}
              <div style={{ marginTop: 20, textAlign: 'right' }}>
                <strong>Total: ${cartTotal.toFixed(2)}</strong>
                <br /><br />
                <button onClick={placeOrder}
                  style={{ padding: '12px 30px', background: '#e94560', color: 'white',
                    border: 'none', borderRadius: 4, cursor: 'pointer', fontSize: 16 }}>
                  Place Order
                </button>
              </div>
            </>
          )}
        </div>
      )}

      {/* Footer */}
      <footer style={{ marginTop: 40, textAlign: 'center', color: '#999', fontSize: 12 }}>
        AKS Production E-Commerce | Running on Azure Kubernetes Service
      </footer>
    </div>
  );
}

export default App;
